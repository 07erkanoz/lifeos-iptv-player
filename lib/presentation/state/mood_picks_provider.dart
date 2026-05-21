import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/personalized_picks_provider.dart'
    show PersonalizedPickCard;
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Mood chips the user can tap to inject a vibe into the rail.
///
/// `key` is a stable ASCII identifier used as both the AI prompt
/// signal and the Riverpod state key. `englishVibe` is the English
/// explainer fed to Gemini — it's English (not localised) so the
/// prompt stays consistent across UI languages.
enum MoodChip {
  relax(
    key: 'relax',
    englishVibe:
        'calm, low-stakes, comforting; the user wants to unwind',
  ),
  thrill(
    key: 'thrill',
    englishVibe:
        'high-stakes tension, fast pace, action or thriller',
  ),
  laugh(
    key: 'laugh',
    englishVibe:
        'pure comedy / feel-good; the user wants to laugh',
  ),
  think(
    key: 'think',
    englishVibe:
        'thought-provoking, slow-burn, ambitious storytelling',
  ),
  nostalgia(
    key: 'nostalgia',
    englishVibe:
        'nostalgic, classic, pre-2010 favourites or remakes of them',
  ),
  surprise(
    key: 'surprise',
    englishVibe:
        'surprise me — pick something outside the user\'s usual genres',
  );

  const MoodChip({required this.key, required this.englishVibe});

  final String key;
  final String englishVibe;
}

/// Currently selected mood chip (or null when no chip is active).
///
/// Tapping a chip toggles it. Tapping it again clears the mood so
/// the rail collapses and the dashboard returns to the default
/// "Sana Özel" state.
class _SelectedMoodNotifier extends Notifier<MoodChip?> {
  @override
  MoodChip? build() => null;

  void select(MoodChip mood) {
    state = state == mood ? null : mood;
  }

  void clear() => state = null;
}

final selectedMoodProvider =
    NotifierProvider<_SelectedMoodNotifier, MoodChip?>(
  _SelectedMoodNotifier.new,
);

/// Process-wide ephemeral cache for mood rails.
///
/// Keyed by [MoodChip], holds the resolved card list. Survives the
/// user toggling between chips during a single dashboard session
/// (so tapping Heyecan → Gülmek → Heyecan again doesn't fire 3 AI
/// calls — the second Heyecan tap returns instantly). Reset when
/// the provider is invalidated or the app restarts.
final _moodSessionCache = <MoodChip, List<PersonalizedPickCard>>{};

/// Future provider for the active mood rail. Returns null when no
/// mood is selected (the rail hides itself). Returns an empty list
/// when AI failed — caller hides too. Otherwise returns the picks
/// ordered by mood fit.
///
/// In-memory session cache keyed by mood, see [_moodSessionCache].
final moodPicksProvider =
    FutureProvider<List<PersonalizedPickCard>?>((ref) async {
  final mood = ref.watch(selectedMoodProvider);
  if (mood == null) return null;

  // Session cache — instant return when the user re-taps a mood
  // they already saw earlier in this session.
  final cached = _moodSessionCache[mood];
  if (cached != null && cached.isNotEmpty) {
    debugPrint('[mood] session cache hit for ${mood.key}');
    return cached;
  }

  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null;

  final contentRepo = ref.watch(contentRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);

  // Same taste signals as the "Sana Özel" rail — the mood
  // overrides genre but the AI still wants context for tone +
  // production quality preferences. Repository helpers JOIN with
  // categories so the AI sees the actual genre signal.
  final historySignals =
      await contentRepo.tasteSignalsFromHistory(limit: 15);
  final favSignals =
      await contentRepo.tasteSignalsFromFavorites(limit: 15);

  // Slightly smaller pool than "Sana Özel" — mood is laser-focused
  // so the AI doesn't need 450 candidates.
  final sample = await contentRepo.sampleLibraryForAi(
    moviesPerType: 150,
    seriesPerType: 150,
    livePerType: 0, // moods are for VOD only
  );

  String escape(String? s) =>
      (s ?? '').replaceAll('|', ' ').replaceAll('\n', ' ').trim();
  final libraryRows = <String>[
    'id|title|type|year|genre|director|cast|rating',
    for (final c in sample.take(350))
      '${c.streamId}|${escape(c.name)}|${c.type}|${escape(c.year)}|${escape(c.genre)}|${escape(c.director)}|${escape(c.cast)}|${c.rating?.toStringAsFixed(1) ?? ""}',
  ];
  final librarySample = [
    {'_format': 'pipe-separated rows', '_rows': libraryRows},
  ];

  final lang = ref.read(settingsProvider).language.name == 'system'
      ? 'tr'
      : ref.read(settingsProvider).language.name;

  // Looked up in the widget for the localised label; but for the AI
  // call we pass the English vibe verbatim — the prompt stays
  // consistent across UI languages.
  final picks = await gemini
      .recommendForMood(
        moodKey: mood.key,
        moodLabel: mood.key, // localised label happens in the widget
        moodDescription: mood.englishVibe,
        recentlyWatched: historySignals,
        favorites: favSignals,
        librarySample: librarySample,
        targetLanguage: lang,
      )
      .timeout(const Duration(seconds: 25), onTimeout: () {
    debugPrint('[mood] AI call timed out for ${mood.key}');
    return null;
  });

  // AI failed or returned empty → fall back to a genre-themed
  // direct DB query so the rail never goes empty for a mood the
  // user explicitly asked for. Querying the DB (not the sample)
  // is critical: a 350-item sample rarely contains enough
  // genre-tagged items of an under-represented mood (e.g. comedy
  // when the catalogue leans action), and falling back to
  // "all-sample top-rated" would surface action titles for a
  // "laugh" request — the bug the user just reported.
  if (picks == null || picks.isEmpty) {
    debugPrint('[mood] AI returned empty for ${mood.key}, '
        'querying DB for genre match');
    final fb = await _dbGenreFallback(mood, db);
    if (fb.isNotEmpty) _moodSessionCache[mood] = fb;
    return fb;
  }

  // Resolve ids to Channel rows. Channels' primary key is
  // (streamId, type) — not streamId alone — so we key by both to
  // avoid losing a movie when a series shares the same numeric id.
  final ids = picks.map((p) => p.streamId).toList();
  final rows = await (db.select(db.channels)
        ..where((t) => t.streamId.isIn(ids)))
      .get();
  final byId = <int, Channel>{};
  for (final c in rows) {
    // Prefer the first row we encounter; subsequent type collisions
    // are rare in Xtream catalogues and dedupe will catch them.
    byId.putIfAbsent(c.streamId, () => c);
  }
  debugPrint('[mood] ${mood.key}: AI picks=${picks.length}, '
      'db-resolved=${byId.length}');

  String normTitle(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'\s*[\(\[\{][^\)\]\}]*[\)\]\}]\s*'), ' ');
    s = s.replaceAll(
        RegExp(r'\b(4k|uhd|hd|fhd|sd|2160p|1080p|720p|480p)\b'), ' ');
    s = s.replaceAll('&', ' and ');
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  String normPoster(String? raw) {
    if (raw == null) return '';
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^https?:\/\/'), '');
    final q = s.indexOf('?');
    if (q != -1) s = s.substring(0, q);
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  final seen = <String>{};
  final out = <PersonalizedPickCard>[];
  for (final pick in picks) {
    final ch = byId[pick.streamId];
    if (ch == null) continue;
    final tKey = 't:${normTitle(ch.name)}';
    final pKey = 'p:${normPoster(ch.streamIcon)}';
    if (tKey != 't:' && seen.contains(tKey)) continue;
    if (pKey != 'p:' && seen.contains(pKey)) continue;
    if (tKey != 't:') seen.add(tKey);
    if (pKey != 'p:') seen.add(pKey);
    out.add(PersonalizedPickCard(channel: ch, reason: pick.reason));
  }
  debugPrint('[mood] ${mood.key}: final cards=${out.length}');
  // Last-ditch fallback: AI returned ids but none survived the
  // resolve+dedupe pass. Still better to show *something* than a
  // "no good match" panel for a mood the user explicitly asked for.
  if (out.isEmpty) {
    debugPrint('[mood] ${mood.key}: all picks dropped, '
        'falling back to DB genre match');
    final fb = await _dbGenreFallback(mood, db);
    if (fb.isNotEmpty) _moodSessionCache[mood] = fb;
    return fb;
  }
  _moodSessionCache[mood] = out;
  return out;
});

/// English-keyword genre / vibe map per mood. Used by the
/// genre-based fallback when the AI call fails or returns nothing
/// resolvable. Each list contains substrings we match against the
/// channel's `genre` column (lower-cased) — keep TR + EN variants
/// so the same map works against catalogues in either language.
const Map<String, List<String>> _moodGenreKeywords = {
  'relax': [
    'family', 'aile', 'romance', 'romantik', 'romantic',
    'feel-good', 'feelgood', 'animation', 'animasyon',
    'kids', 'çocuk', 'cocuk',
  ],
  'thrill': [
    'action', 'aksiyon', 'thriller', 'gerilim', 'crime', 'suç', 'suc',
    'mystery', 'gizem', 'adventure', 'macera', 'spy', 'casus',
    'heist', 'soygun',
  ],
  'laugh': [
    'comedy', 'komedi', 'sitcom', 'humor', 'humour', 'mizah',
    'romantic comedy', 'romkom', 'satire', 'satir',
    'parody', 'parodi', 'stand-up', 'standup', 'standup-komedi',
  ],
  'think': [
    'drama', 'mystery', 'gizem', 'sci-fi', 'science fiction',
    'bilim kurgu', 'documentary', 'belgesel', 'biography',
    'biyografi', 'history', 'tarih', 'philosophical', 'felsefi',
  ],
  'nostalgia': [
    'classic', 'klasik', 'romance', 'romantik', 'romantic',
    'drama', 'family', 'aile', 'musical', 'müzikal', 'muzikal',
  ],
  'surprise': [
    // No genre filter — pure variety. Returns a shuffled slice of
    // the top-rated catalogue, see _dbGenreFallback for that path.
  ],
};

/// Direct-from-DB genre fallback.
///
/// Crucially we match on BOTH `channels.genre` AND the parent
/// `categories.name` — most Xtream catalogues ship with the genre
/// column empty (28k of the user's 27,629 movies had no genre on
/// inspection) but encode the genre into the category label
/// instead, e.g. "KOMEDi & ROMANTiK", "KORKU & PSiKOLOJiK",
/// "AKSiYON & MACERA & GiZEM". Looking only at `channels.genre`
/// produced 0 comedy matches for the user; joining categories
/// recovers ~thousands of correctly-genre'd items.
///
/// For the "surprise" mood we deliberately have no genre keywords;
/// in that case we return the top-rated 10 VOD items globally,
/// because surprise is supposed to be unpredictable variety.
Future<List<PersonalizedPickCard>> _dbGenreFallback(
    MoodChip mood, AppDatabase db) async {
  final kws = _moodGenreKeywords[mood.key] ?? const [];

  // Pull VOD joined with its category. Hidden categories filtered
  // out the same way the rest of the search does.
  final rows = await (db.select(db.channels).join([
    leftOuterJoin(
      db.categories,
      db.categories.id.equalsExp(db.channels.categoryId) &
          db.categories.type.equalsExp(db.channels.type),
    ),
  ])
        ..where((db.channels.type.equals('movie') |
                db.channels.type.equals('series')) &
            (db.categories.isHidden.equals(false) |
                db.categories.isHidden.isNull())))
      .get();
  if (rows.isEmpty) return const [];

  // Each row → (channel, categoryName). Some channels may have
  // null category from the left join (orphan / hidden).
  final pairs = rows.map((r) {
    final ch = r.readTable(db.channels);
    final cat = r.readTableOrNull(db.categories);
    return (channel: ch, categoryName: cat?.name ?? '');
  }).toList();

  // Always exclude adult-tagged categories from mood rails — the
  // user can still find those via direct search, but a mood-of-the-
  // moment rail surfacing them is jarring. Common Xtream conventions:
  // "For Adult*", "ADLT*", category labels containing "erotic" / "xxx".
  bool isAdult(String catName, String chName) {
    final c = catName.toLowerCase();
    final n = chName.toLowerCase();
    return c.contains('adult') ||
        c.contains('erotic') ||
        c.contains('xxx') ||
        c.contains('porn') ||
        n.startsWith('adlt');
  }

  Iterable<({Channel channel, String categoryName})> pool = pairs.where(
      (p) => !isAdult(p.categoryName, p.channel.name));
  if (kws.isNotEmpty) {
    pool = pool.where((p) {
      // Match against EITHER the genre column OR the category
      // name. The category-name match is what saves us when the
      // genre column is empty (the common case).
      final g = p.channel.genre?.toLowerCase() ?? '';
      final c = p.categoryName.toLowerCase();
      if (g.isEmpty && c.isEmpty) return false;
      return kws.any((kw) {
        final k = kw.toLowerCase();
        return g.contains(k) || c.contains(k);
      });
    });
  }
  final filtered = pool.toList();
  debugPrint(
      '[mood] DB fallback ${mood.key}: ${filtered.length} matches '
      'across genre + category name');

  // Hard rule: if we can't find at least 3 matches we return EMPTY
  // instead of falling through to wrong-genre top-rated. Showing
  // action films for "Laugh" is worse than showing the "couldn't
  // find a match" panel — the user explicitly asked for a mood.
  if (kws.isNotEmpty && filtered.length < 3) {
    return const [];
  }

  // Rank by rating desc so the dud-floor is decent.
  final ranked = filtered
      .map((p) => p.channel)
      .toList()
    ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

  // Same two-key dedupe (title + poster) as the AI path so multi-
  // category Xtream re-listings don't show up twice.
  final seen = <String>{};
  final out = <PersonalizedPickCard>[];
  for (final ch in ranked) {
    if (out.length >= 10) break;
    var t = ch.name.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s*[\(\[\{][^\)\]\}]*[\)\]\}]\s*'), ' ');
    t = t.replaceAll('&', ' and ');
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    var p = (ch.streamIcon ?? '').toLowerCase();
    final q = p.indexOf('?');
    if (q != -1) p = p.substring(0, q);
    final tKey = 't:$t';
    final pKey = 'p:$p';
    if (t.isNotEmpty && seen.contains(tKey)) continue;
    if (p.isNotEmpty && seen.contains(pKey)) continue;
    if (t.isNotEmpty) seen.add(tKey);
    if (p.isNotEmpty) seen.add(pKey);
    out.add(PersonalizedPickCard(channel: ch, reason: ''));
  }

  // Surprise mood with empty filtered (no kws → falls through to
  // ranked = all VOD): take a randomised slice instead of just the
  // top-rated head, because "surprise" with the same top-10 each
  // time isn't surprising.
  if (mood == MoodChip.surprise) {
    final shuffled = ranked.take(100).toList()..shuffle();
    return shuffled.take(10).map((ch) {
      return PersonalizedPickCard(channel: ch, reason: '');
    }).toList();
  }

  return out;
}
