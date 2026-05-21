import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/ai_rail_cache_repository.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Resolved AI hero billboard — Channel rows in the order the AI
/// wants them shown, paired with the per-item tagline that the
/// hero overlay renders right below the title.
class HeroBillboard {
  final List<Channel> channels;
  final Map<int, String> taglines; // keyed by streamId

  const HeroBillboard({required this.channels, required this.taglines});

  bool get isEmpty => channels.isEmpty;
}

/// FutureProvider for the AI hero billboard.
///
/// Returns null when:
///   * the user has no Gemini key, OR
///   * the AI call failed (caller falls back to the non-AI hero
///     item list so the dashboard never goes dark).
///
/// Cached for the lifetime of the Riverpod container — one call
/// per app session. The hero doesn't need to refresh aggressively;
/// most users restart the app multiple times a week, and the
/// underlying library state changes much slower than the rail.
final heroBillboardProvider =
    FutureProvider<HeroBillboard?>((ref) async {
  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null;

  final contentRepo = ref.watch(contentRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  final cache = ref.watch(aiRailCacheRepositoryProvider);

  // ── Compute the fingerprint we'll use as a cache key ─────────────
  // Pull just the IDs of the user's top taste signals (small query)
  // before deciding whether we need the heavy sample + AI work. If
  // the fingerprint matches and cache is fresh, we skip everything
  // below and return cached picks directly.
  final histIds = await (db.select(db.playbackProgress)
        ..where((t) => t.position.isBiggerThanValue(0))
        ..orderBy([
          (t) => OrderingTerm(
              expression: t.updatedAt, mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final favIds = await (db.select(db.favorites)
        ..orderBy([
          (t) => OrderingTerm(
              expression: t.addedAt, mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;
  final timeOfDay = _bucketOfDay(DateTime.now());

  // Cheap probe: max `added` timestamp across VOD. Folded into the
  // fingerprint so any new content landing in the catalogue auto-
  // invalidates the cached hero — we WANT the hero to react to new
  // items, that's the whole point of the recent-additions prompt.
  final newest = await (db.selectOnly(db.channels)
        ..addColumns([db.channels.added])
        ..where(db.channels.type.equals('movie') |
            db.channels.type.equals('series'))
        ..orderBy([
          OrderingTerm(
              expression: db.channels.added, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .map((row) => row.read(db.channels.added) ?? '')
      .getSingleOrNull();

  // Fold language + time-bucket + newest-added into the fingerprint.
  final fpBlob = 'hero-v2|lang=$lang|tod=$timeOfDay'
      '|n=${newest ?? ""}'
      '|h=${(histIds.map((r) => r.streamId).toList()..sort()).join(",")}'
      '|f=${(favIds.map((r) => r.streamId).toList()..sort()).join(",")}';
  final sourceHash = AiRailCacheRepository.fingerprint(fpBlob);

  // Cache lookup — 24 h TTL. The hero rotates every day-ish, which
  // matches how often the time-bucket bumps the fingerprint too.
  final cached = cache.lookup(
    cacheKey: 'hero_billboard',
    sourceHash: sourceHash,
    ttl: const Duration(hours: 24),
  );
  if (cached != null) {
    final ids = (cached['ids'] as List?)?.cast<int>() ?? const [];
    final taglineMap =
        (cached['taglines'] as Map?)?.cast<String, String>() ?? const {};
    if (ids.isNotEmpty) {
      final rows = await (db.select(db.channels)
            ..where((t) => t.streamId.isIn(ids)))
          .get();
      final byId = <int, Channel>{};
      for (final c in rows) {
        byId.putIfAbsent(c.streamId, () => c);
      }
      final channels = <Channel>[];
      final taglines = <int, String>{};
      for (final id in ids) {
        final ch = byId[id];
        if (ch == null) continue;
        channels.add(ch);
        taglines[id] = taglineMap[id.toString()] ?? '';
      }
      if (channels.isNotEmpty) {
        debugPrint('[hero] cache hit ($sourceHash), '
            '${channels.length} channels resolved');
        return HeroBillboard(channels: channels, taglines: taglines);
      }
    }
  }
  debugPrint('[hero] cache miss, calling Gemini');

  // ── Cache miss → full pipeline ────────────────────────────────────
  // Rich taste signals via the repository helpers — these JOIN with
  // categories so the per-item map includes the catalog category
  // label, which is the only place the genre actually lives on this
  // user's Xtream feed.
  final historySignals =
      await contentRepo.tasteSignalsFromHistory(limit: 12);
  final favSignals =
      await contentRepo.tasteSignalsFromFavorites(limit: 12);

  // ── Recent additions pool ─────────────────────────────────────────
  // The hero's primary job is to surface what's new in the catalogue.
  // Pull the freshest VOD by the Xtream `added` timestamp (text-typed
  // Unix epoch, so we can't push the order into SQL — sort in Dart
  // after a bounded fetch). Filter for items that have a backdrop or
  // at least a poster so the hero panel doesn't render broken.
  final allVod = await (db.select(db.channels)
        ..where((t) => t.type.equals('movie') | t.type.equals('series'))
        ..limit(2000))
      .get();
  int parseAdded(Channel c) =>
      int.tryParse(c.added?.trim() ?? '') ?? 0;
  final sortedByAdded = allVod.toList()
    ..sort((a, b) => parseAdded(b).compareTo(parseAdded(a)));
  final recentWithArt = sortedByAdded
      .where((c) =>
          (c.backdropPath != null && c.backdropPath!.isNotEmpty) ||
          (c.streamIcon != null && c.streamIcon!.isNotEmpty))
      .take(80)
      .toList();

  // ── Broader well-rated sample ─────────────────────────────────────
  // Variety net so the AI has fallback candidates when RECENT_ADDITIONS
  // doesn't fit the user's taste. Strict backdrop filter again.
  final sample = await contentRepo.sampleLibraryForAi(
    moviesPerType: 120,
    seriesPerType: 120,
    livePerType: 0,
  );
  final withBackdrop = sample
      .where((c) =>
          (c.backdropPath != null && c.backdropPath!.isNotEmpty) ||
          (c.streamIcon != null && c.streamIcon!.isNotEmpty))
      .toList();
  final pool = withBackdrop.length >= 50 ? withBackdrop : sample;

  String escape(String? s) =>
      (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
  String rowOf(Channel c) =>
      '${c.streamId}|${escape(c.name)}|${c.type}|${escape(c.year)}|${escape(c.genre)}|${escape(c.director)}|${escape(c.cast)}|${c.rating?.toStringAsFixed(1) ?? ""}';
  final header = 'id|title|type|year|genre|director|cast|rating';

  final recentAdditionsPayload = recentWithArt.isEmpty
      ? <Map<String, dynamic>>[]
      : [
          {
            '_format': 'pipe-separated rows, newest-first',
            '_rows': [
              header,
              for (final c in recentWithArt) rowOf(c),
            ],
          },
        ];

  // Dedupe LIBRARY_HIGHLIGHTS against RECENT_ADDITIONS so the AI
  // doesn't see the same item in both pools and get confused about
  // which signal applies.
  final recentIds = recentWithArt.map((c) => c.streamId).toSet();
  final librarySample = [
    {
      '_format': 'pipe-separated rows',
      '_rows': [
        header,
        for (final c in pool.take(220))
          if (!recentIds.contains(c.streamId)) rowOf(c),
      ],
    },
  ];

  final picks = await gemini
      .generateHeroBillboard(
        recentlyWatched: historySignals,
        favorites: favSignals,
        recentAdditions: recentAdditionsPayload,
        librarySample: librarySample,
        timeOfDay: timeOfDay,
        targetLanguage: lang,
      )
      .timeout(const Duration(seconds: 20), onTimeout: () => null);

  if (picks == null || picks.isEmpty) return null;

  // Resolve to Channel rows in the order AI picked them.
  final ids = picks.map((p) => p.streamId).toList();
  final rows = await (db.select(db.channels)
        ..where((t) => t.streamId.isIn(ids)))
      .get();
  final byId = {for (final c in rows) c.streamId: c};
  final ordered = <Channel>[];
  final taglines = <int, String>{};
  final seen = <int>{};
  for (final pick in picks) {
    final ch = byId[pick.streamId];
    if (ch == null) continue;
    if (!seen.add(pick.streamId)) continue;
    ordered.add(ch);
    taglines[pick.streamId] = pick.tagline;
  }
  if (ordered.isEmpty) return null;

  // Persist for the next 24 h. Only ids + taglines go to disk;
  // the heavy Channel rows are re-hydrated on cache hit, so even
  // if the underlying metadata changes the cards stay accurate.
  await cache.store(
    cacheKey: 'hero_billboard',
    sourceHash: sourceHash,
    payload: {
      'ids': ordered.map((c) => c.streamId).toList(),
      'taglines':
          taglines.map((k, v) => MapEntry(k.toString(), v)),
    },
  );
  debugPrint('[hero] cached ${ordered.length} picks under $sourceHash');

  return HeroBillboard(channels: ordered, taglines: taglines);
});

String _bucketOfDay(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'sabah';
  if (h >= 11 && h < 17) return 'öğle';
  if (h >= 17 && h < 22) return 'akşam';
  return 'gece';
}
