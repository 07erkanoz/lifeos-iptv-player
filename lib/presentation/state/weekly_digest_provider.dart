import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/ai_rail_cache_repository.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/ai_instrumentation_service.dart';
import 'package:lifeostv/data/services/ai_model_policy.dart';
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
  final cache = ref.watch(aiRailCacheRepositoryProvider);

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

  // ── Cache check ───────────────────────────────────────────────────
  // Fingerprint over the ids of the chosen recent slice + language.
  // The slice changes when new content arrives, so the fingerprint
  // auto-invalidates next week without us having to track it.
  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;
  final recentIds = recentRows.map((c) => c.streamId).toList()..sort();
  final fpBlob =
      'digest-v1|lang=$lang|r=${recentIds.take(50).join(",")}';
  final sourceHash = AiRailCacheRepository.fingerprint(fpBlob);

  // 3-day TTL — the rail is supposed to feel weekly but we want it
  // to react reasonably promptly when the user marks something
  // unwatched or favorites a new title (those don't bump the
  // fingerprint, but the TTL bound means the digest never stays
  // truly stale for more than a few days).
  final cached = cache.lookup(
    cacheKey: 'weekly_digest',
    sourceHash: sourceHash,
    ttl: const Duration(days: 3),
  );
  if (cached != null) {
    final headline = cached['headline'] as String? ?? '';
    final ids = (cached['ids'] as List?)?.cast<int>() ?? const [];
    final reasonMap =
        (cached['reasons'] as Map?)?.cast<String, String>() ?? const {};
    if (headline.isNotEmpty && ids.isNotEmpty) {
      final byId = {for (final c in recentRows) c.streamId: c};
      final channels = <Channel>[];
      final reasons = <int, String>{};
      for (final id in ids) {
        final ch = byId[id];
        if (ch == null) continue;
        channels.add(ch);
        reasons[id] = reasonMap[id.toString()] ?? '';
      }
      if (channels.isNotEmpty) {
        debugPrint('[digest] cache hit ($sourceHash)');
        return WeeklyDigest(
            headline: headline, channels: channels, reasons: reasons);
      }
    }
  }
  debugPrint('[digest] cache miss, calling Gemini');

  // Rich taste signals via repository helpers — these JOIN with
  // categories so the AI sees the actual catalog genre labels.
  final contentRepo = ref.watch(contentRepositoryProvider);
  final favSignals =
      await contentRepo.tasteSignalsFromFavorites(limit: 12);
  final historySignals =
      await contentRepo.tasteSignalsFromHistory(limit: 12);

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

  final instrumentation = ref.read(aiInstrumentationProvider);
  final result = await instrumentation.record<
      ({String headline, List<({int streamId, String reason})> picks})>(
    feature: 'weeklyDigest',
    model: AiModelPolicy.dashboardRanking,
    candidateCount: recentRows.length,
    outputCountOf: (r) => r.picks.length,
    timeout: const Duration(seconds: 20),
    run: () => gemini.weeklyDigest(
      recentAdditions: recentAdditions,
      favorites: favSignals,
      recentlyWatched: historySignals,
      targetLanguage: lang,
    ),
  );

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

  // Persist for the next 3 days.
  await cache.store(
    cacheKey: 'weekly_digest',
    sourceHash: sourceHash,
    payload: {
      'headline': result.headline,
      'ids': channels.map((c) => c.streamId).toList(),
      'reasons':
          reasons.map((k, v) => MapEntry(k.toString(), v)),
    },
  );
  debugPrint('[digest] cached ${channels.length} picks under $sourceHash');

  return WeeklyDigest(
    headline: result.headline,
    channels: channels,
    reasons: reasons,
  );
});
