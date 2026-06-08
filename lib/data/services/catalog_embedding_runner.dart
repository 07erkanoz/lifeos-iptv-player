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

  CatalogEmbeddingRunner(this._repo, this._gemini);

  bool _running = false;

  // High cap — embeddings are cheap and 64/batch, so a single run can
  // clear most catalogues. _running guards against overlap.
  Future<int> runOnce({int maxBatchesPerRun = 300}) async {
    final gemini = _gemini;
    if (gemini == null || _running) return 0;
    _running = true;
    var embedded = 0;
    var consecutiveFailures = 0;
    try {
      for (var i = 0; i < maxBatchesPerRun; i++) {
        final pending = await _repo.pendingItems(limit: _batchSize);
        if (pending.isEmpty) break;

        final vectors = await gemini.embedTexts(
          [for (final p in pending) p.text],
          dims: _dims,
        );
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
        final companions = <ContentEmbeddingsCompanion>[];
        for (var j = 0; j < n; j++) {
          final vec = vectors[j];
          if (vec.isEmpty) continue;
          final norm = ContentEmbeddingsRepository.normalize(vec);
          companions.add(ContentEmbeddingsCompanion.insert(
            streamId: pending[j].streamId,
            type: pending[j].type,
            vector: ContentEmbeddingsRepository.encode(norm),
            dims: norm.length,
            updatedAt: Value(DateTime.now()),
          ));
        }
        await _repo.storeBatch(companions);
        embedded += companions.length;
        if (kDebugMode) {
          debugPrint('[embed] batch ${i + 1}: +${companions.length} '
              '(total $embedded)');
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

final catalogEmbeddingRunnerProvider =
    Provider<CatalogEmbeddingRunner>((ref) {
  return CatalogEmbeddingRunner(
    ref.watch(contentEmbeddingsRepositoryProvider),
    ref.watch(geminiServiceProvider),
  );
});
