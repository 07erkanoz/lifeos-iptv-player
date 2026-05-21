import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/personalized_picks_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
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

/// Bumped each time the user taps the rail's refresh button. The
/// main provider watches this — non-zero values force the cache
/// lookup to be skipped and are passed to Gemini as a variety seed
/// so the new picks visibly differ from the previous ones.
///
/// Riverpod 3 dropped `StateProvider`, hence the tiny Notifier.
class _PersonalizedPicksRefreshSeed extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = DateTime.now().millisecondsSinceEpoch;
}

/// SharedPreferences key under which we persist a JSON snapshot of
/// the last-rendered rail. Read SYNCHRONOUSLY on app start by
/// [personalizedPicksSnapshotProvider] so the dashboard can paint
/// the rail in the first frame instead of flashing the shimmer
/// for the duration of the async cache lookup + Channel resolve
/// chain (~100-300 ms even on a warm Drift cache hit).
const _personalizedSnapshotKey = 'personalized_picks_snapshot_v1';

/// Synchronous fallback provider for the rail.
///
/// Reads the last-rendered snapshot directly from SharedPreferences
/// (which is initialised before Riverpod and exposes getString()
/// synchronously). The widget renders this on the first frame while
/// the async [personalizedPicksProvider] runs in the background.
/// Once the async provider lands fresh data the widget swaps over.
///
/// Returns null when:
///   * the user has no Gemini key (matching the rest of the rail's
///     hide-when-no-key behaviour),
///   * the snapshot was never written, or
///   * the snapshot fails to parse.
final personalizedPicksSnapshotProvider =
    Provider<List<PersonalizedPickCard>?>((ref) {
  // Mirror the async provider's no-key gate so the snapshot doesn't
  // briefly flash for users who later removed their key.
  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null;
  final prefs = ref.watch(sharedPreferencesProvider);
  final raw = prefs.getString(_personalizedSnapshotKey);
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final out = <PersonalizedPickCard>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final streamId = (item['streamId'] as num?)?.toInt();
      final name = item['name']?.toString();
      final type = item['type']?.toString();
      if (streamId == null || name == null || type == null) continue;
      // Construct a *minimal* Channel object — enough to render the
      // tile and route the onTap callback. Other fields default to
      // null; downstream consumers (detail page) re-fetch the full
      // row by (streamId, type) from Drift.
      final channel = Channel(
        streamId: streamId,
        name: name,
        type: type,
        categoryId: '',
        streamIcon: item['streamIcon'] as String?,
      );
      out.add(PersonalizedPickCard(
        channel: channel,
        reason: item['reason']?.toString() ?? '',
      ));
    }
    return out.isEmpty ? null : out;
  } catch (e) {
    debugPrint('[snapshot] decode failed: $e');
    return null;
  }
});

/// Persist the resolved rail snapshot for the next cold start.
/// Called by the async provider after every successful resolve so
/// the snapshot stays accurate as the user's taste drifts.
Future<void> _savePersonalizedSnapshot(
  Ref ref,
  List<PersonalizedPickCard> cards,
) async {
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    final json = jsonEncode([
      for (final c in cards)
        {
          'streamId': c.channel.streamId,
          'name': c.channel.name,
          'type': c.channel.type,
          'streamIcon': c.channel.streamIcon,
          'reason': c.reason,
        },
    ]);
    await prefs.setString(_personalizedSnapshotKey, json);
  } catch (_) {
    // Snapshot write is best-effort; failure just means the next
    // cold start falls back to the standard shimmer + async fetch.
  }
}

final personalizedPicksRefreshSeedProvider =
    NotifierProvider<_PersonalizedPicksRefreshSeed, int>(
  _PersonalizedPicksRefreshSeed.new,
);

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

  // Refresh nonce — bumped by the rail's refresh button. When
  // non-zero we skip the cache entirely and pass the seed to Gemini
  // so it samples differently from its last response.
  final refreshSeed = ref.watch(personalizedPicksRefreshSeedProvider);

  // Gather current taste state. The repository helpers join
  // channels with categories so each signal map includes the
  // category label — critical signal since `channels.genre` is
  // mostly NULL on Xtream catalogues. We pull more favourites
  // than history because favourites are the stronger signal and
  // we want the AI to see the full saved-for-later pattern.
  final historySignals =
      await contentRepo.tasteSignalsFromHistory(limit: 25);
  final favSignals =
      await contentRepo.tasteSignalsFromFavorites(limit: 25);

  // Channel-row lookups still needed for the background-refresh
  // fingerprint + the resolver. We pull the IDs from the signal
  // maps and rehydrate Channel rows in one round-trip below.
  final historyIds = historySignals
      .map((m) => (m['id'] as num?)?.toInt())
      .whereType<int>()
      .toList();
  final favoriteIds = favSignals
      .map((m) => (m['id'] as num?)?.toInt())
      .whereType<int>()
      .toList();
  final channelRows = await (db.select(db.channels)
        ..where((t) =>
            t.streamId.isIn({...historyIds, ...favoriteIds})))
      .get();
  final byId = {for (final c in channelRows) c.streamId: c};
  final history = [
    for (final id in historyIds)
      if (byId[id] != null) byId[id]!,
  ];
  final favorites = [
    for (final id in favoriteIds)
      if (byId[id] != null) byId[id]!,
  ];

  final sourceHash = PersonalizedPicksRepository.fingerprint(
    recentlyWatchedIds: history.map((c) => c.streamId),
    favoriteIds: favorites.map((c) => c.streamId),
  );

  // Cache check — skipped entirely on an explicit refresh so the
  // user always gets a fresh AI run when they hit the button.
  if (refreshSeed == 0) {
    final cached = await cacheRepo.lookup(sourceHash: sourceHash);
    if (cached != null && cached.isNotEmpty) {
      return _resolveAndSnapshot(cached, db, ref);
    }

    // ── Stale-while-revalidate ──────────────────────────────────
    // Fingerprint missed (the user's taste signals drifted since
    // the cache was written — they watched something new, favourited
    // something, etc.). Rather than block the rail behind a fresh
    // 5-15 second AI call, return the previous cached row instantly
    // and kick off the refresh in the background. Next dashboard
    // open lands the fresh result.
    final stale = await cacheRepo.lookupLatest();
    if (stale != null && stale.isNotEmpty) {
      // Fire-and-forget background refresh. Wrapped in microtask so
      // the provider returns the stale picks immediately rather than
      // racing the AI call. When the call lands we update the cache
      // and invalidate the provider so the UI re-renders with the
      // fresh picks on the next paint.
      Future.microtask(() => _refreshInBackground(
            ref: ref,
            gemini: gemini,
            contentRepo: contentRepo,
            cacheRepo: cacheRepo,
            historySignals: historySignals,
            favSignals: favSignals,
            sourceHash: sourceHash,
          ));
      return _resolveAndSnapshot(stale, db, ref);
    }
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

  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;

  // Hard 20-second cap on the AI call. Without this, a hung
  // Gemini would leave the provider in an indefinite loading
  // state and the rail would shimmer forever.
  //
  // The taste-signal maps come from the repository helpers, which
  // include the category label — the real genre signal on this
  // catalogue since channels.genre is mostly NULL.
  final picks = await gemini
      .recommendForYou(
        recentlyWatched: historySignals,
        favorites: favSignals,
        librarySample: librarySample,
        targetLanguage: lang,
        varietySeed: refreshSeed,
      )
      .timeout(const Duration(seconds: 20), onTimeout: () => null);

  if (picks != null && picks.isNotEmpty) {
    await cacheRepo.store(sourceHash: sourceHash, picks: picks);
    return _resolveAndSnapshot(picks, db, ref);
  }

  // AI returned null (failure) or empty (no good matches). Try
  // the latest cached row regardless of fingerprint — a slightly-
  // out-of-date rail beats an empty one.
  final fallback = await cacheRepo.lookupLatest();
  if (fallback != null && fallback.isNotEmpty) {
    return _resolveAndSnapshot(fallback, db, ref);
  }

  // Last resort: synthesise a rail from the top-rated sample we
  // already pulled. No ✨ reasons (the cards just render bare
  // posters in this state), but the user sees a populated rail
  // instead of blank space.
  if (sample.isEmpty) return null;
  // Dedupe by *normalised title + poster URL* — multi-category
  // Xtream catalogues routinely re-list the same VOD under several
  // stream ids, sometimes with different localised titles (e.g.
  // "La Disparue de la cabine 10" + "10 Numaralı Kamara" pointing
  // at the same TMDB poster). Two-key dedupe catches both flavours.
  final seen = <String>{};
  final fallbackPicks = <Channel>[];
  for (final ch in sample) {
    if (!_claimDedupeSlot(ch, seen)) continue;
    fallbackPicks.add(ch);
    if (fallbackPicks.length >= 15) break;
  }
  if (fallbackPicks.isEmpty) return null;
  return [
    for (final ch in fallbackPicks)
      PersonalizedPickCard(channel: ch, reason: ''),
  ];
});

/// Fire-and-forget background refresh used by the stale-while-
/// revalidate path. Runs the full Gemini pipeline silently in the
/// background; when it succeeds, writes the fresh row to the cache
/// and invalidates the provider so the UI re-renders with the new
/// picks on the next paint.
///
/// Wrapped in `try/catch` because any error here would surface as
/// an unhandled future — a refresh failing shouldn't crash the app,
/// the user already has stale-but-usable data on screen.
Future<void> _refreshInBackground({
  required Ref ref,
  required GeminiService gemini,
  required ContentRepository contentRepo,
  required PersonalizedPicksRepository cacheRepo,
  required List<Map<String, dynamic>> historySignals,
  required List<Map<String, dynamic>> favSignals,
  required String sourceHash,
}) async {
  try {
    final sample = await contentRepo.sampleLibraryForAi(
      moviesPerType: 200,
      seriesPerType: 200,
      livePerType: 30,
    );
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
    final lang = ref.read(settingsProvider).language.name == 'system'
        ? 'tr'
        : ref.read(settingsProvider).language.name;
    final picks = await gemini
        .recommendForYou(
          recentlyWatched: historySignals,
          favorites: favSignals,
          librarySample: librarySample,
          targetLanguage: lang,
        )
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (picks == null || picks.isEmpty) return;
    await cacheRepo.store(sourceHash: sourceHash, picks: picks);
    // Surface the fresh data by invalidating the provider. Any
    // exception (e.g. the container has already been disposed
    // because the user navigated away) is swallowed below — the
    // cache write already landed for the next session.
    ref.invalidate(personalizedPicksProvider);
  } catch (_) {
    // Silent — the user already has stale picks on screen, and a
    // background failure shouldn't surface as anything visible.
  }
}

/// Aggressively normalise a title for dedupe: lowercase, strip
/// punctuation, drop year suffixes like " (2020)" / " [2020]", drop
/// quality suffixes like " 4K"/" HD", collapse whitespace.
///
/// Xtream catalogues sometimes re-list the same VOD with subtle
/// variations ("Mike & Nick" vs "Mike and Nick (2020)" vs "Mike &
/// Nick HD"). Plain lowercase-trim missed those; this catches them.
String _normaliseTitle(String raw) {
  var s = raw.toLowerCase().trim();
  // Strip trailing year markers, language tags, quality tags.
  s = s.replaceAll(RegExp(r'\s*[\(\[\{][^\)\]\}]*[\)\]\}]\s*'), ' ');
  s = s.replaceAll(
      RegExp(r'\b(4k|uhd|hd|fhd|sd|2160p|1080p|720p|480p)\b'), ' ');
  // & → and so variants collapse.
  s = s.replaceAll('&', ' and ');
  // Strip everything that isn't a letter/digit/space.
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  // Collapse whitespace.
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Normalise a poster URL so two slightly different URLs pointing
/// at the same TMDB poster collapse. Strips protocol + query string
/// + trailing slash; the path itself is what identifies the asset.
String _normalisePoster(String? raw) {
  if (raw == null) return '';
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^https?:\/\/'), '');
  final q = s.indexOf('?');
  if (q != -1) s = s.substring(0, q);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s;
}

/// Returns true if [ch] is a fresh entry — registers its dedupe
/// keys in [seen] and reports back. Returns false if either the
/// normalised title or the poster URL has been seen before.
///
/// Two-key dedupe catches Xtream's multi-language re-listings:
/// "La Disparue de la cabine 10" (FR) and "10 Numaralı Kamara" (TR)
/// are textually unrelated, but they share the same TMDB poster, so
/// the URL fingerprint collapses them. Title-only dedupe still
/// catches "Mike & Nick" vs "Mike and Nick (2020)" where titles
/// are close but posters might be missing.
bool _claimDedupeSlot(Channel ch, Set<String> seen) {
  final titleKey = 't:${_normaliseTitle(ch.name)}';
  final posterKey = 'p:${_normalisePoster(ch.streamIcon)}';
  final hasTitle = titleKey != 't:';
  final hasPoster = posterKey != 'p:';
  if (!hasTitle && !hasPoster) return false;
  if (hasTitle && seen.contains(titleKey)) return false;
  if (hasPoster && seen.contains(posterKey)) return false;
  if (hasTitle) seen.add(titleKey);
  if (hasPoster) seen.add(posterKey);
  return true;
}

/// Resolve a list of picks (id + reason) into renderable cards by
/// looking up the full Channel row for each id. Missing ids — e.g.
/// the channel was deleted between caching and rendering — are
/// silently dropped. Cards are deduped by normalised title so
/// multi-category Xtream catalogues that carry the same VOD under
/// multiple stream ids don't render the same poster five times.
/// Wrapper around [_resolve] that also persists the rendered cards
/// to the synchronous snapshot used by [personalizedPicksSnapshotProvider].
/// All happy-path resolves in the provider should go through this
/// so the next cold start can paint instantly from SharedPreferences.
Future<List<PersonalizedPickCard>> _resolveAndSnapshot(
  List<PersonalizedPick> picks,
  AppDatabase db,
  Ref ref,
) async {
  final resolved = await _resolve(picks, db);
  if (resolved.isNotEmpty) {
    // Fire-and-forget — snapshot write should never block the
    // rail rendering.
    unawaited(_savePersonalizedSnapshot(ref, resolved));
  }
  return resolved;
}

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
  final seen = <String>{};
  for (final pick in picks) {
    final ch = byId[pick.streamId];
    if (ch == null) continue;
    if (!_claimDedupeSlot(ch, seen)) continue;
    out.add(PersonalizedPickCard(channel: ch, reason: pick.reason));
  }
  return out;
}
