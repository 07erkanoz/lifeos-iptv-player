import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/personalized_picks_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// One personalised pick resolved to a real channel row, paired with
/// its AI-supplied reason.
class PersonalizedPickCard {
  final Channel channel;
  final String reason;

  const PersonalizedPickCard({
    required this.channel,
    required this.reason,
  });
}

/// Future provider for the "Sana Özel" dashboard rail.
///
/// Returns `null` when:
///   * the user has no Gemini key configured, or
///   * the AI call failed and there's no usable cache.
///
/// Returns an empty list when AI consulted but couldn't find good
/// picks (rare — usually means the library is too small).
///
/// Otherwise returns the AI-curated cards in the order Gemini
/// ranked them. The dashboard widget consumes this and hides the
/// rail entirely on null.
///
/// Behaviour:
///   1. Build the source fingerprint from the current
///      recently-watched + favourites snapshot.
///   2. Look up the singleton cache row. Cache hit (matching
///      fingerprint, within TTL) → resolve ids to Channel rows
///      and return.
///   3. Cache miss → call Gemini with a compact pipe-separated
///      library sample, store the result, return resolved.
///   4. AI failure → fall back to whatever the cache had even if
///      stale, so the rail doesn't blink empty on transient
///      errors. Pure cache failures (never been populated) just
///      return null.
final personalizedPicksProvider =
    FutureProvider<List<PersonalizedPickCard>?>((ref) async {
  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null; // No key → no rail.

  final cacheRepo = ref.watch(personalizedPicksRepositoryProvider);
  final contentRepo = ref.watch(contentRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);

  // Gather current taste state. Both queries are cheap joins,
  // single round-trip apiece.
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
        ..limit(20))
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
        ..limit(20))
      .get();
  final favorites =
      favRows.map((row) => row.readTable(db.channels)).toList();

  final sourceHash = PersonalizedPicksRepository.fingerprint(
    recentlyWatchedIds: history.map((c) => c.streamId),
    favoriteIds: favorites.map((c) => c.streamId),
  );

  // Cache check.
  final cached = await cacheRepo.lookup(sourceHash: sourceHash);
  if (cached != null && cached.isNotEmpty) {
    return _resolve(cached, db);
  }

  // Library sample — bigger than the search curator's because
  // the rail is the user's first impression and we want variety
  // to spread across types and genres.
  final sample = await contentRepo.sampleLibraryForAi(
    moviesPerType: 200,
    seriesPerType: 200,
    livePerType: 30,
  );

  // Build compact pipe-rows payload — same format as the search
  // curator so prompt costs stay predictable.
  String escape(String? s) =>
      (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
  final libraryRows = <String>[
    'id|title|type|year|genre|director|cast|rating',
    for (final c in sample.take(450))
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
        if (c.director != null && c.director!.isNotEmpty)
          'director': c.director,
      };

  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;

  final picks = await gemini.recommendForYou(
    recentlyWatched: history.map(compactWatch).toList(),
    favorites: favorites.map(compactWatch).toList(),
    librarySample: librarySample,
    targetLanguage: lang,
  );

  if (picks == null) {
    // AI failure — keep last known good if any, otherwise null.
    // We deliberately bypass the fingerprint check here because
    // showing slightly-stale picks is better than blinking the
    // whole rail out.
    final fallback = await cacheRepo.lookup(
      sourceHash: sourceHash,
      ttl: const Duration(days: 7),
    );
    if (fallback != null && fallback.isNotEmpty) {
      return _resolve(fallback, db);
    }
    return null;
  }

  if (picks.isEmpty) {
    return const [];
  }

  await cacheRepo.store(sourceHash: sourceHash, picks: picks);
  return _resolve(picks, db);
});

/// Resolve a list of picks (id + reason) into renderable cards by
/// looking up the full Channel row for each id. Missing ids — e.g.
/// the channel was deleted between caching and rendering — are
/// silently dropped.
Future<List<PersonalizedPickCard>> _resolve(
  List<PersonalizedPick> picks,
  AppDatabase db,
) async {
  if (picks.isEmpty) return const [];
  final ids = picks.map((p) => p.streamId).toList();
  final rows = await (db.select(db.channels)
        ..where((t) => t.streamId.isIn(ids)))
      .get();
  final byId = {for (final c in rows) c.streamId: c};
  final out = <PersonalizedPickCard>[];
  for (final pick in picks) {
    final ch = byId[pick.streamId];
    if (ch != null) {
      out.add(PersonalizedPickCard(channel: ch, reason: pick.reason));
    }
  }
  return out;
}
