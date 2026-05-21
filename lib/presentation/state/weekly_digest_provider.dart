import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Resolved weekly digest — a headline + a list of newly-added
/// items the AI thinks the user will care about.
class WeeklyDigest {
  final String headline;
  final List<Channel> channels;
  final Map<int, String> reasons; // keyed by streamId

  const WeeklyDigest({
    required this.headline,
    required this.channels,
    required this.reasons,
  });
}

/// FutureProvider for the dashboard weekly-digest banner.
///
/// Returns null when:
///   * the user has no Gemini key, OR
///   * fewer than 4 items were added to the library in the last 7
///     days (banner would feel forced with too little input), OR
///   * the user dismissed the banner less than 7 days ago, OR
///   * the AI call failed.
///
/// Computed once per app session; the banner widget handles dismiss
/// state by writing the timestamp back into AppSettings.
final weeklyDigestProvider =
    FutureProvider<WeeklyDigest?>((ref) async {
  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null;

  final settings = ref.watch(settingsProvider);
  final lastDismissed = settings.lastDigestDismissedAt;
  if (lastDismissed != null) {
    final age = DateTime.now().difference(lastDismissed);
    if (age < const Duration(days: 7)) return null;
  }

  final db = ref.watch(appDatabaseProvider);

  // Pull VOD/series and rank by the Xtream-provided `added` string
  // (Unix timestamp as text). We can't push the comparison into the
  // SQL where-clause because the column is text, so we fetch a
  // bounded slice and rank in Dart.
  final allVod = await (db.select(db.channels)
        ..where((t) => t.type.equals('movie') | t.type.equals('series'))
        ..limit(2000))
      .get();
  if (allVod.isEmpty) return null;

  int parseAdded(Channel c) {
    final raw = c.added?.trim();
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? 0;
  }

  // Sort by `added` desc, then keep only the items added within the
  // last 7 days. If fewer than 4 made the cutoff, broaden to the 30
  // most recently added overall — the AI still tags them with a
  // useful "new to your library" lens.
  final sorted = allVod.toList()
    ..sort((a, b) => parseAdded(b).compareTo(parseAdded(a)));
  final sevenDaysAgoEpoch =
      DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/
          1000;
  var recentRows = sorted
      .where((c) => parseAdded(c) >= sevenDaysAgoEpoch)
      .toList();
  if (recentRows.length < 4) {
    recentRows = sorted.take(30).toList();
  }
  if (recentRows.length < 4) return null;

  // Taste signals — favourites + history, smaller pull than the
  // rail provider since the digest is tightly scoped to "this week".
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

  final histRows = await (db.select(db.channels).join([
    innerJoin(
      db.playbackProgress,
      db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
          db.playbackProgress.type.equalsExp(db.channels.type),
    ),
  ])
        ..orderBy([
          OrderingTerm(
              expression: db.playbackProgress.updatedAt,
              mode: OrderingMode.desc),
        ])
        ..limit(10))
      .get();
  final history =
      histRows.map((row) => row.readTable(db.channels)).toList();

  String escape(String? s) =>
      (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
  final libraryRows = <String>[
    'id|title|type|year|genre|director|cast|rating',
    for (final c in recentRows.take(120))
      '${c.streamId}|${escape(c.name)}|${c.type}|${escape(c.year)}|${escape(c.genre)}|${escape(c.director)}|${escape(c.cast)}|${c.rating?.toStringAsFixed(1) ?? ""}',
  ];
  final recentAdditions = [
    {'_format': 'pipe-separated rows', '_rows': libraryRows},
  ];

  Map<String, dynamic> compact(Channel c) => {
        'id': c.streamId,
        'title': c.name,
        'type': c.type,
        if (c.genre != null && c.genre!.isNotEmpty) 'genre': c.genre,
        if (c.director != null && c.director!.isNotEmpty)
          'director': c.director,
      };

  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;

  final result = await gemini
      .weeklyDigest(
        recentAdditions: recentAdditions,
        favorites: favorites.map(compact).toList(),
        recentlyWatched: history.map(compact).toList(),
        targetLanguage: lang,
      )
      .timeout(const Duration(seconds: 20), onTimeout: () => null);

  if (result == null) return null;

  // Resolve ids to Channel rows.
  final byId = {for (final c in recentRows) c.streamId: c};
  final channels = <Channel>[];
  final reasons = <int, String>{};
  for (final pick in result.picks) {
    final ch = byId[pick.streamId];
    if (ch == null) continue;
    channels.add(ch);
    reasons[pick.streamId] = pick.reason;
  }
  if (channels.isEmpty) return null;
  return WeeklyDigest(
    headline: result.headline,
    channels: channels,
    reasons: reasons,
  );
});
