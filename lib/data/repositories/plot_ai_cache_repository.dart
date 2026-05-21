import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'plot_ai_cache_repository.g.dart';

/// Persistent cache for AI-enriched plot text on the detail page.
///
/// Lifecycle:
///   * `lookup(...)` — called by `PlotEnrichedView._enrich` before
///     hitting Gemini. Returns the cached text when the row exists
///     *and* its `sourceHash` still matches the current input
///     (otherwise it's stale and we re-fetch).
///   * `store(...)` — called right after a successful AI call,
///     `InsertMode.insertOrReplace` so stale rows are overwritten.
///   * `clear(streamId)` — point invalidation when the user does
///     something explicit (re-syncs, deletes account…). Not called
///     automatically; the hash check already handles drift in
///     metadata.
///
/// `sourceHash` is the fingerprint of (title|year|genre|director|
/// cast|rating|plot). A weak hash is fine here — we're not
/// guarding integrity, just detecting "this source changed".
class PlotAiCacheRepository {
  final AppDatabase _db;

  PlotAiCacheRepository(this._db);

  /// Returns the cached enrichment for this `(streamId, mode,
  /// targetLanguage)` tuple if it was generated from the same
  /// source the caller is now looking at. Stale rows (different
  /// hash) and absent rows both return `null` — caller falls back
  /// to a fresh AI call.
  Future<String?> lookup({
    required int streamId,
    required PlotEnrichMode mode,
    required String targetLanguage,
    required String sourceHash,
  }) async {
    final row = await (_db.select(_db.plotAiCache)
          ..where((t) => t.streamId.equals(streamId))
          ..where((t) => t.mode.equals(mode.name))
          ..where((t) => t.targetLanguage.equals(targetLanguage))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.sourceHash != sourceHash) return null;
    return row.content;
  }

  /// Upsert a row. `mode` is stored as its enum name string so the
  /// table doesn't break if PlotEnrichMode gains entries later.
  Future<void> store({
    required int streamId,
    required PlotEnrichMode mode,
    required String targetLanguage,
    required String sourceHash,
    required String content,
  }) async {
    await _db.into(_db.plotAiCache).insert(
          PlotAiCacheCompanion.insert(
            streamId: streamId,
            mode: mode.name,
            targetLanguage: targetLanguage,
            content: content,
            sourceHash: sourceHash,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Drop every cached enrichment for one title. Used as a hook for
  /// future "refresh" UI; current code paths rely on hash-based
  /// auto-invalidation and never call this.
  Future<void> clear(int streamId) async {
    await (_db.delete(_db.plotAiCache)
          ..where((t) => t.streamId.equals(streamId)))
        .go();
  }

  /// Hardcoded prompt-and-config version. Bumped whenever the
  /// system prompt or generation config in
  /// [GeminiService.enrichPlot] materially changes — old cache
  /// rows produced under the previous configuration carry a
  /// different hash and re-fetch automatically.
  ///
  /// Bump history:
  ///   * v1 — initial (900-token detailedInfo budget,
  ///     UNKNOWN sentinel).
  ///   * v2 — UNKNOWN sentinel removed.
  ///   * v3 — director/cast/rating added to the user turn,
  ///     detailedInfo token budget raised to 4096.
  static const _promptVersion = 'v3';

  /// Cheap fingerprint of the metadata we feed Gemini. Same input →
  /// same hash → cache hit. Any change to any field (sync ran and
  /// the plot is now different, user updated the channel, etc.)
  /// changes the hash and invalidates the row.
  ///
  /// Includes [_promptVersion] so bumping the prompt or output
  /// budget invalidates the cache even with identical channel
  /// metadata. Users who paid for a truncated reply don't stay
  /// stuck with it after the budget is raised.
  ///
  /// Static so callers don't need a repo instance just to compute
  /// a hash — they can hash the channel locally and only touch
  /// the DB when they actually want to read/write.
  static String fingerprint({
    required String title,
    String? year,
    String? genre,
    String? director,
    String? cast,
    double? rating,
    String? originalPlot,
  }) {
    final blob = [
      _promptVersion,
      title,
      year ?? '',
      genre ?? '',
      director ?? '',
      cast ?? '',
      rating?.toStringAsFixed(1) ?? '',
      originalPlot ?? '',
    ].join(''); // SOH as field separator — won't appear in normal text
    // Dart's built-in Object.hashCode is stable within a process
    // but not guaranteed across runs/platforms; for our use case
    // (cache invalidation), even that's enough — if the hash
    // happens to differ on a restart we just re-fetch once. For
    // robustness we use a simple FNV-1a 32-bit roll, which is
    // deterministic across runs.
    var h = 0x811c9dc5;
    for (final code in blob.codeUnits) {
      h = (h ^ code) & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

@riverpod
PlotAiCacheRepository plotAiCacheRepository(Ref ref) {
  return PlotAiCacheRepository(ref.watch(appDatabaseProvider));
}
