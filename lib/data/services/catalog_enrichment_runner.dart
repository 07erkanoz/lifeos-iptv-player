import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_enrichment_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Background filler for the [ContentEnrichment] table.
///
/// Walks the catalogue in newest-first chunks, asks Gemini to infer the
/// missing genre / year / mood / themes, and writes the results back to
/// Drift. Designed to be:
///   * **Resumable** — `pendingItems()` only ever returns rows that
///     aren't enriched yet, so each run naturally picks up where the
///     last left off, across app launches.
///   * **Bounded** — capped at [maxBatchesPerRun] batches per call so a
///     single app-open never hammers the API; the rest happens on the
///     next launch.
///   * **Throttled** — a pause between batches keeps us under the
///     Flash-Lite free-tier RPM ceiling.
///   * **Gated** — the caller only invokes this when the user has a
///     Gemini key AND opted in.
class CatalogEnrichmentRunner {
  // Smaller batches keep each structured-JSON response well under the
  // output-token cap (a 30-item Turkish response could truncate →
  // unparseable → looked like a "stop"). 18 is a safe ceiling.
  static const int _batchSize = 18;
  static const Duration _betweenBatches = Duration(seconds: 4);
  // Backoff after a failed/empty batch (likely a transient rate-limit
  // or a one-off bad response) before we retry the same items.
  static const Duration _afterFailure = Duration(seconds: 12);

  final ContentEnrichmentRepository _repo;
  final GeminiService? _gemini;
  final String _targetLanguage;

  CatalogEnrichmentRunner(this._repo, this._gemini, this._targetLanguage);

  bool _running = false;

  /// Process up to [maxBatchesPerRun] batches. No-op when there's no
  /// Gemini key or a run is already in flight. Returns how many items
  /// were enriched this call.
  Future<int> runOnce({int maxBatchesPerRun = 8}) async {
    final gemini = _gemini;
    if (gemini == null || _running) return 0;
    _running = true;
    var enriched = 0;
    var consecutiveFailures = 0;
    try {
      for (var i = 0; i < maxBatchesPerRun; i++) {
        final pending = await _repo.pendingItems(limit: _batchSize);
        if (pending.isEmpty) break; // everything enriched — done

        final input = [
          for (final c in pending)
            (
              streamId: c.streamId,
              type: c.type,
              title: c.name,
              year: c.year,
              cast: c.cast,
              director: c.director,
            )
        ];
        final results =
            await gemini.enrichCatalogBatch(input, targetLanguage: _targetLanguage);
        if (results == null || results.isEmpty) {
          // Transient failure (rate-limit / one-off bad response).
          // Don't kill the whole run on the first hit — back off and
          // retry the same items a couple of times before giving up.
          consecutiveFailures++;
          if (kDebugMode) {
            debugPrint('[enrich] batch ${i + 1} empty/failed '
                '(fail $consecutiveFailures)');
          }
          if (consecutiveFailures >= 3) break;
          await Future<void>.delayed(_afterFailure);
          continue;
        }
        consecutiveFailures = 0;

        // Only persist ids we actually asked about (guard against any
        // hallucinated rows), and only when the model echoed a usable id.
        final asked = {for (final c in pending) c.streamId};
        final typeOf = {for (final c in pending) c.streamId: c.type};
        final returned = <int>{};
        final companions = <ContentEnrichmentCompanion>[];
        for (final r in results) {
          final sid = (r['streamId'] as num?)?.toInt();
          final type = r['type'] as String?;
          if (sid == null || type == null || !asked.contains(sid)) continue;
          returned.add(sid);
          companions.add(ContentEnrichmentCompanion(
            streamId: Value(sid),
            type: Value(type),
            genres: Value(_clean(r['genres'])),
            year: Value((r['year'] as num?)?.toInt()),
            moodTags: Value(_clean(r['mood'])),
            themes: Value(_clean(r['themes'])),
            contentWarnings: Value(_clean(r['warnings'])),
            ageRating: Value(_clean(r['age'])),
            confidence: Value((r['confidence'] as num?)?.toDouble()),
            source: const Value('text'),
            updatedAt: Value(DateTime.now()),
          ));
        }
        // Tombstone the items the model OMITTED from a successful batch.
        // Without this they stay at the front of the newest-first queue
        // and get re-sent on every batch forever — the catalogue looks
        // "stuck" at a number. A placeholder row (null genres) removes
        // them from `pendingItems` so the queue always moves forward.
        for (final c in pending) {
          if (returned.contains(c.streamId)) continue;
          companions.add(ContentEnrichmentCompanion(
            streamId: Value(c.streamId),
            type: Value(typeOf[c.streamId] ?? c.type),
            source: const Value('text'),
            confidence: const Value(0),
            updatedAt: Value(DateTime.now()),
          ));
        }
        await _repo.storeBatch(companions);
        enriched += returned.length;
        if (kDebugMode) {
          debugPrint('[enrich] batch ${i + 1}: +${returned.length} '
              '(${companions.length - returned.length} skipped) total $enriched');
        }
        await Future<void>.delayed(_betweenBatches);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[enrich] run failed: $e');
    } finally {
      _running = false;
    }
    return enriched;
  }

  static String? _clean(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

final catalogEnrichmentRunnerProvider =
    Provider<CatalogEnrichmentRunner>((ref) {
  final lang = ref.read(settingsProvider).language.name;
  return CatalogEnrichmentRunner(
    ref.watch(contentEnrichmentRepositoryProvider),
    ref.watch(geminiServiceProvider),
    lang == 'system' ? 'tr' : lang,
  );
});
