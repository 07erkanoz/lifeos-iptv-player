import 'package:lifeostv/core/playback_signal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';

/// Background filler for [ContentEmbeddings]. Walks the catalogue in
/// newest-first chunks, asks Gemini for a vector per title (built from
/// the enriched text), L2-normalises it, and writes it to Drift.
///
/// Same shape as the enrichment runner: resumable (pendingItems only
/// returns un-embedded rows), bounded per call, throttled, gated on a
/// Gemini key. Embedding is cheap, so this can run fast on paid tiers.
class CatalogEmbeddingRunner {
  static const int _batchSize = 64;
  static const int _dims = 768;
  static const Duration _betweenBatches = Duration(seconds: 1);
  static const Duration _afterFailure = Duration(seconds: 10);

  final ContentEmbeddingsRepository _repo;
  final GeminiService? _gemini;

  CatalogEmbeddingRunner(
    this._repo,
    this._gemini, {
    bool Function()? shouldPause,
  }) : _shouldPause = shouldPause ?? (() => playbackActiveNotifier.value);

  final bool Function() _shouldPause;
  bool _cancelled = false;
  bool get _stopped => _cancelled || _shouldPause();
  void cancel() => _cancelled = true;

  bool _running = false;

  // Moderate cap (64/batch → ~2560 items/run). Short enough that
  // _running clears promptly; the 45s periodic re-kick continues.
  Future<int> runOnce({int maxBatchesPerRun = 40}) async {
    final gemini = _gemini;
    if (gemini == null || _running || _stopped) return 0;
    _running = true;
    var embedded = 0;
    var consecutiveFailures = 0;
    try {
      for (var i = 0; i < maxBatchesPerRun; i++) {
        if (_stopped) break;
        final pending = await _repo.pendingItems(limit: _batchSize);
        if (_stopped || pending.isEmpty) break;

        final vectors = await gemini.embedTexts([
          for (final p in pending) p.text,
        ], dims: _dims);
        if (_stopped) break;
        if (vectors == null || vectors.isEmpty) {
          consecutiveFailures++;
          if (consecutiveFailures >= 3) break;
          await Future<void>.delayed(_afterFailure);
          continue;
        }
        consecutiveFailures = 0;

        // Zip by index up to the shorter length (the API returns
        // vectors in request order).
        final n = pending.length < vectors.length
            ? pending.length
            : vectors.length;
        final companions =
            <({EmbeddingInput source, ContentEmbeddingsCompanion vector})>[];
        for (var j = 0; j < n; j++) {
          final vec = vectors[j];
          if (vec.length != _dims || vec.any((v) => !v.isFinite)) continue;
          final norm = ContentEmbeddingsRepository.normalize(vec);
          if (norm.isEmpty) continue;
          companions.add((
            source: pending[j],
            vector: ContentEmbeddingsCompanion.insert(
              streamId: pending[j].streamId,
              type: pending[j].type,
              vector: ContentEmbeddingsRepository.encode(norm),
              dims: norm.length,
              updatedAt: Value(DateTime.now()),
            ),
          ));
        }
        if (_stopped) break;
        final written = await _repo.storeCurrentBatch(
          companions,
          shouldCancel: () => _stopped,
        );
        embedded += written;
        if (kDebugMode) {
          debugPrint(
            '[embed] batch ${i + 1}: +$written '
            '(total $embedded)',
          );
        }
        await Future<void>.delayed(_betweenBatches);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[embed] run failed: $e');
    } finally {
      _running = false;
    }
    return embedded;
  }
}

final catalogEmbeddingRunnerProvider = Provider<CatalogEmbeddingRunner>((ref) {
  final runner = CatalogEmbeddingRunner(
    ref.watch(contentEmbeddingsRepositoryProvider),
    ref.watch(geminiServiceProvider),
  );
  ref.onDispose(runner.cancel);
  return runner;
});
