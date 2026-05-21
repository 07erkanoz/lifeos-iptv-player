import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
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

  // Taste signals — same as the rail providers but slightly smaller
  // since the hero is a tighter pick.
  final historyRows = await (db.select(db.channels).join([
    innerJoin(
      db.playbackProgress,
      db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
          db.playbackProgress.type.equalsExp(db.channels.type),
    ),
  ])
        ..where(db.playbackProgress.position.isBiggerThanValue(0))
        ..orderBy([
          OrderingTerm(
              expression: db.playbackProgress.updatedAt,
              mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final history =
      historyRows.map((row) => row.readTable(db.channels)).toList();

  final favRows = await (db.select(db.channels).join([
    innerJoin(
      db.favorites,
      db.favorites.streamId.equalsExp(db.channels.streamId) &
          db.favorites.streamType.equalsExp(db.channels.type),
    ),
  ])
        ..orderBy([
          OrderingTerm(
              expression: db.favorites.addedAt, mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final favorites =
      favRows.map((row) => row.readTable(db.channels)).toList();

  // The hero NEEDS backdrops to look right. Bias the sample toward
  // well-rated mainstream titles so AI has good candidates.
  final sample = await contentRepo.sampleLibraryForAi(
    moviesPerType: 120,
    seriesPerType: 120,
    livePerType: 0, // hero is VOD-only
  );

  String escape(String? s) =>
      (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
  // Only feed AI candidates that have backdrops — billboard items
  // without a hero image look broken. Falls back to all items if
  // backdrop-tagged ones are too sparse.
  final withBackdrop = sample
      .where((c) =>
          (c.backdropPath != null && c.backdropPath!.isNotEmpty) ||
          (c.streamIcon != null && c.streamIcon!.isNotEmpty))
      .toList();
  final pool = withBackdrop.length >= 50 ? withBackdrop : sample;
  final libraryRows = <String>[
    'id|title|type|year|genre|director|cast|rating',
    for (final c in pool.take(300))
      '${c.streamId}|${escape(c.name)}|${c.type}|${escape(c.year)}|${escape(c.genre)}|${escape(c.director)}|${escape(c.cast)}|${c.rating?.toStringAsFixed(1) ?? ""}',
  ];
  final librarySample = [
    {'_format': 'pipe-separated rows', '_rows': libraryRows},
  ];

  Map<String, dynamic> compactWatch(Channel c) => {
        'id': c.streamId,
        'title': c.name,
        'type': c.type,
        if (c.year != null && c.year!.isNotEmpty) 'year': c.year,
        if (c.genre != null && c.genre!.isNotEmpty) 'genre': c.genre,
      };

  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;
  final timeOfDay = _bucketOfDay(DateTime.now());

  final picks = await gemini
      .generateHeroBillboard(
        recentlyWatched: history.map(compactWatch).toList(),
        favorites: favorites.map(compactWatch).toList(),
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
  return HeroBillboard(channels: ordered, taglines: taglines);
});

String _bucketOfDay(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'sabah';
  if (h >= 11 && h < 17) return 'öğle';
  if (h >= 17 && h < 22) return 'akşam';
  return 'gece';
}
