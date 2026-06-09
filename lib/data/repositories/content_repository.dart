import 'package:drift/drift.dart';
// `show debugPrint` only, because `package:flutter/foundation.dart`
// re-exports its own `Category` annotation which collides with our
// generated drift `Category` row class.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/search_intent.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/utils/search_normalizer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'content_repository.g.dart';

class ContentRepository {
  final AppDatabase _db;
  final SyncService _syncService;
  final int Function() _getActiveProfileId;

  /// Minimum interval between full EPG syncs (server-friendly)
  static const _epgSyncInterval = Duration(hours: 2);
  static const _epgSyncKey = 'last_epg_sync_timestamp';

  ContentRepository(this._db, this._syncService, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  Stream<List<Category>> watchCategories(String type) {
    return (_db.select(_db.categories)
      ..where((tbl) => tbl.type.equals(type))
      ..where((tbl) => tbl.isHidden.equals(false))
    ).watch();
  }

  /// All categories including hidden ones (for editing)
  Stream<List<Category>> watchAllCategories(String type) {
    return (_db.select(_db.categories)..where((tbl) => tbl.type.equals(type))).watch();
  }

  /// Toggle category visibility. Writes both the live `categories`
  /// flag (for immediate UI) AND a timestamped `category_prefs` row —
  /// the durable source of truth that survives catalogue refreshes
  /// (which insertOrReplace the categories table and would otherwise
  /// wipe the flag) and is synced across paired devices (LWW).
  Future<void> toggleCategoryHidden(String categoryId, String type, bool hidden) async {
    await (_db.update(_db.categories)
      ..where((tbl) => tbl.id.equals(categoryId) & tbl.type.equals(type))
    ).write(CategoriesCompanion(isHidden: Value(hidden)));
    await _db.into(_db.categoryPrefs).insertOnConflictUpdate(
      CategoryPrefsCompanion.insert(
        categoryId: categoryId,
        type: type,
        isHidden: Value(hidden),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Re-apply saved category-visibility prefs onto the `categories`
  /// table. Called after a catalogue refresh (which resets isHidden to
  /// the default) and after a LAN sync adopts a peer's prefs, so the
  /// user's hide choices always stick. No-op when no prefs exist.
  Future<void> reapplyCategoryPrefs() async {
    final prefs = await _db.select(_db.categoryPrefs).get();
    if (prefs.isEmpty) return;
    await _db.batch((batch) {
      for (final p in prefs) {
        batch.update(
          _db.categories,
          CategoriesCompanion(isHidden: Value(p.isHidden)),
          where: (tbl) =>
              tbl.id.equals(p.categoryId) & tbl.type.equals(p.type),
        );
      }
    });
  }

  Stream<List<Channel>> watchChannels(String categoryId, {String? type}) {
    final query = _db.select(_db.channels)
      ..where((tbl) => tbl.categoryId.equals(categoryId));
    if (type != null) {
      query.where((tbl) => tbl.type.equals(type));
    }
    // Overlay AI enrichment so empty-genre items show their inferred
    // genre/year in the grid, the genre filter, AND the detail page
    // (which receives the channel object from the grid tap).
    return query.watch().asyncMap(_mergeEnrichment);
  }

  /// All channels of a given type (no limit — for "Tüm" grid + search)
  /// Filters out channels from hidden categories.
  Stream<List<Channel>> watchAllChannelsByType(String type) {
    final query = _db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
      ..orderBy([OrderingTerm(expression: _db.channels.added, mode: OrderingMode.desc)]);
    return query
        .watch()
        .map((rows) => rows.map((row) => row.readTable(_db.channels)).toList())
        .asyncMap(_mergeEnrichment);
  }

  /// Recent channels filtered by hidden categories.
  Stream<List<Channel>> watchRecentChannels(String type, {int limit = 20}) {
    final query = _db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
      ..orderBy([OrderingTerm(expression: _db.channels.added, mode: OrderingMode.desc)])
      ..limit(limit);
    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Search channels by name across all types.
  ///
  /// Uses [SearchNormalizer] so Turkish + Latin diacritics fold to
  /// ASCII on both sides (`İnterstellar` matches `interstellar`,
  /// `Şımarık` matches `simarik`). Multi-token queries do AND match
  /// over a joined haystack of title + cast + director + genre +
  /// category name — typing "matthew interstellar" lands the film
  /// even though the second token is the title and the first lives
  /// in the cast column.
  ///
  /// Filters out channels from hidden categories.
  Future<List<Channel>> searchChannels(String query, {int limit = 50}) async {
    final tokens = SearchNormalizer.tokens(query);
    if (tokens.isEmpty) return const [];
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])..where(_db.categories.isHidden.equals(false))).get();
    // Preload enrichment once so genre-less items can still match a
    // genre query ("korku") and the returned channel carries the
    // inferred genre.
    final enrich = await _loadEnrichmentMap();
    final out = <Channel>[];
    for (final row in rows) {
      if (out.length >= limit) break;
      final ch = _applyEnrichment(row.readTable(_db.channels), enrich);
      final cat = row.readTable(_db.categories);
      final haystack = _buildHaystack(ch, cat);
      if (SearchNormalizer.matches(haystack, tokens)) {
        out.add(ch);
      }
    }
    return out;
  }

  /// Pre-normalised concatenation of every searchable text column on
  /// a channel + its category. Used by every search code path so the
  /// matching semantics stay consistent: title, category name, cast,
  /// director, genre, plot keywords, year.
  ///
  /// Plot is included but pre-trimmed to the first 200 chars — long
  /// IPTV plots are noisy and inflating the haystack with their full
  /// text causes spurious matches (every plot mentioning "film"
  /// matching the token "film").
  static String _buildHaystack(Channel ch, Category? cat) {
    final plot = ch.plot ?? '';
    final plotSnippet = plot.length > 200 ? plot.substring(0, 200) : plot;
    return SearchNormalizer.normalise([
      ch.name,
      cat?.name ?? '',
      ch.cast ?? '',
      ch.director ?? '',
      ch.genre ?? '',
      ch.year ?? '',
      plotSnippet,
    ].join(' '));
  }

  /// Compact taste-signal records used by every AI recommendation
  /// provider. Joins channels with categories so the per-item map
  /// includes the category label — critical because the user's
  /// catalogue stores almost no data in `channels.genre` (the genre
  /// is encoded in the category name like "KOMEDi & ROMANTiK").
  ///
  /// Without the category join the AI gets `{title, year}` triples
  /// with no taste signal beyond the title, leading to bland
  /// recommendations.
  Future<List<Map<String, dynamic>>> tasteSignalsFromHistory({
    int limit = 25,
  }) async {
    final rows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
            _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where(_db.playbackProgress.position.isBiggerThanValue(0) &
              _db.playbackProgress.profileId.equals(_pid) &
              (_db.categories.isHidden.equals(false) |
                  _db.categories.id.isNull()))
          ..orderBy([
            OrderingTerm(
                expression: _db.playbackProgress.updatedAt,
                mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows.map((r) {
      final ch = r.readTable(_db.channels);
      final cat = r.readTableOrNull(_db.categories);
      return <String, dynamic>{
        'id': ch.streamId,
        'title': ch.name,
        'type': ch.type,
        if (ch.year != null && ch.year!.isNotEmpty) 'year': ch.year,
        if (ch.genre != null && ch.genre!.isNotEmpty) 'genre': ch.genre,
        if (cat != null && cat.name.isNotEmpty) 'category': cat.name,
        if (ch.director != null && ch.director!.isNotEmpty)
          'director': ch.director,
        if (ch.cast != null && ch.cast!.isNotEmpty)
          'cast': _trimCast(ch.cast!),
      };
    }).toList();
  }

  /// Same shape as [tasteSignalsFromHistory] but sourced from the
  /// favourites table. Favourites are a stronger taste signal than
  /// recently-watched (users save what they love; they watch what
  /// happens to be available), so callers usually weight these
  /// higher in their prompts.
  Future<List<Map<String, dynamic>>> tasteSignalsFromFavorites({
    int limit = 25,
  }) async {
    final rows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.favorites,
        _db.favorites.streamId.equalsExp(_db.channels.streamId) &
            _db.favorites.streamType.equalsExp(_db.channels.type),
      ),
      leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where(_db.favorites.profileId.equals(_pid) &
              (_db.categories.isHidden.equals(false) |
                  _db.categories.id.isNull()))
          ..orderBy([
            OrderingTerm(
                expression: _db.favorites.addedAt,
                mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows.map((r) {
      final ch = r.readTable(_db.channels);
      final cat = r.readTableOrNull(_db.categories);
      return <String, dynamic>{
        'id': ch.streamId,
        'title': ch.name,
        'type': ch.type,
        if (ch.year != null && ch.year!.isNotEmpty) 'year': ch.year,
        if (ch.genre != null && ch.genre!.isNotEmpty) 'genre': ch.genre,
        if (cat != null && cat.name.isNotEmpty) 'category': cat.name,
        if (ch.director != null && ch.director!.isNotEmpty)
          'director': ch.director,
        if (ch.cast != null && ch.cast!.isNotEmpty)
          'cast': _trimCast(ch.cast!),
      };
    }).toList();
  }

  /// Trim a comma-separated cast string to the first 3 names so the
  /// taste-signal payload doesn't balloon. Three top-billed names
  /// are enough for the AI to spot recurring actor patterns.
  static String _trimCast(String raw) {
    final names = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    return names.join(', ');
  }

  /// Common Turkish ↔ English country/language synonyms. The chat
  /// assistant matches user-typed words like "korean" against the
  /// catalogue's Turkish-labelled categories like "KORE DiZiLERi"
  /// (and vice versa) by expanding through this map before the
  /// haystack search. Without this expansion, "best Korean dramas"
  /// returned zero results on a TR-localised catalogue even though
  /// the user had 173 series under KORE DiZiLERi.
  static const Map<String, List<String>> _countrySynonyms = {
    'korean': ['korean', 'kore'],
    'kore': ['kore', 'korean'],
    'japanese': ['japanese', 'japon'],
    'japon': ['japon', 'japanese'],
    'chinese': ['chinese', 'çin', 'cin'],
    'çin': ['çin', 'cin', 'chinese'],
    'cin': ['cin', 'çin', 'chinese'],
    'spanish': ['spanish', 'ispanyol', 'latino'],
    'ispanyol': ['ispanyol', 'spanish'],
    'french': ['french', 'fransız', 'fransiz'],
    'fransız': ['fransız', 'fransiz', 'french'],
    'fransiz': ['fransız', 'fransiz', 'french'],
    'turkish': ['turkish', 'türk', 'turk', 'türkiye'],
    'türk': ['türk', 'turk', 'turkish'],
    'turk': ['turk', 'türk', 'turkish'],
    'german': ['german', 'alman'],
    'alman': ['alman', 'german'],
    'italian': ['italian', 'italyan'],
    'italyan': ['italyan', 'italian'],
    'russian': ['russian', 'rus'],
    'rus': ['rus', 'russian'],
    'indian': ['indian', 'hint', 'bollywood'],
    'hint': ['hint', 'indian', 'bollywood'],
    'bollywood': ['bollywood', 'hint', 'indian'],
    'series': ['series', 'dizi', 'dizisi', 'dizileri'],
    'dizi': ['dizi', 'dizisi', 'dizileri', 'series'],
    'movie': ['movie', 'film', 'filmler'],
    'film': ['film', 'filmler', 'movie'],
    'drama': ['drama', 'dram'],
    'dram': ['dram', 'drama'],
  };

  /// Stopwords stripped from the chat-assistant keyword query so a
  /// prompt like "en iyi Kore dizilerini listele" lowers to {kore,
  /// dizileri, listele} → {kore, dizi, dizileri, dizisi, series}.
  static const Set<String> _chatStopwords = {
    'the', 'and', 'for', 'with', 'from', 'best', 'good', 'great',
    'top', 'list', 'show', 'recommend', 'tell', 'find',
    've', 'ile', 'için', 'icin', 'bir', 'bana', 'sen', 'ben',
    'en', 'iyi', 'güzel', 'guzel', 'liste', 'listele', 'göster',
    'goster', 'öner', 'oner', 'söyle', 'soyle', 'bul', 'getir',
    'var', 'mi', 'mı', 'mu', 'mü', 'olan', 'olanları', 'olanlari',
    'uygulamada', 'uygulama', 'kütüphane', 'kutuphane',
    'kütüphanede', 'kutuphanede',
  };

  /// Free-text library search used by the chat assistant before the
  /// recommendForTonight call. Expands query words through the
  /// country/language synonym map, then matches against an aggregate
  /// haystack of (channel name + category name + cast + director +
  /// genre).
  ///
  /// Critical for queries like "en iyi Kore dizilerini listele" —
  /// the standard 30-row top-rated sample never contained Korean
  /// dramas (they're not top-rated in this user's catalogue), so the
  /// AI confidently said "yok" even though 173 sat under
  /// KORE DiZiLERi. This pre-search pumps the actual matches into
  /// the AI's prompt context.
  Future<List<Channel>> librarySearchByKeywords(
    String query, {
    int limit = 60,
  }) async {
    // Normalise via the shared SearchNormalizer so İ/ş/ğ/ü etc. are
    // folded the same way as the search screen's plain-LIKE path.
    // Drop chat stopwords so "filmleri öner" tokenises to {filmler}
    // rather than dragging in {oner, filmleri, oner}.
    final normalised = SearchNormalizer.normalise(query);
    final rawTokens = normalised
        .replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_chatStopwords.contains(w))
        .toSet();
    if (rawTokens.isEmpty) return const [];

    // Expand synonyms — both country/language and genre.
    final expanded = <String>{};
    for (final t in rawTokens) {
      expanded.add(t);
      final cs = _countrySynonyms[t];
      if (cs != null) expanded.addAll(cs.map(SearchNormalizer.normalise));
      final gs = _genreSynonyms[t];
      if (gs != null) expanded.addAll(gs.map(SearchNormalizer.normalise));
    }

    // Pull a wide VOD slice joined with categories, ranked by
    // rating. We filter in Dart because building dynamic-OR LIKE
    // chains across both Channel and Category columns in Drift gets
    // verbose and the bounded 5k-row scan is sub-50 ms on the
    // user's catalogue.
    final rows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where((_db.channels.type.equals('movie') |
                  _db.channels.type.equals('series')) &
              _db.categories.isHidden.equals(false))
          ..orderBy([
            OrderingTerm(
                expression: _db.channels.rating,
                mode: OrderingMode.desc),
          ])
          ..limit(5000))
        .get();

    final out = <Channel>[];
    for (final r in rows) {
      if (out.length >= limit) break;
      final ch = r.readTable(_db.channels);
      final cat = r.readTableOrNull(_db.categories);
      final haystack = _buildHaystack(ch, cat);
      if (expanded.any(haystack.contains)) {
        out.add(ch);
      }
    }
    return out;
  }

  /// Compact summary of the library's category structure used by the
  /// chat assistant prompt — gives the AI an at-a-glance view of
  /// what's actually in the user's catalogue beyond the top-rated
  /// sample, so it doesn't say "yok" when asked about niche genres
  /// like Korean dramas that just aren't in the rating-sorted slice.
  ///
  /// Returns the top [limit] non-hidden categories by item count,
  /// each as `{name, type, count}`. Adult categories are stripped
  /// the same way the rest of the AI surface treats them.
  Future<List<Map<String, dynamic>>> categoryOverview({
    int limit = 60,
  }) async {
    final countExpr = _db.channels.streamId.count();
    final rows = await (_db.select(_db.categories).join([
      innerJoin(
        _db.channels,
        _db.channels.categoryId.equalsExp(_db.categories.id) &
            _db.channels.type.equalsExp(_db.categories.type),
      ),
    ])
          ..addColumns([countExpr])
          ..where(_db.categories.isHidden.equals(false))
          ..groupBy([_db.categories.id, _db.categories.type])
          ..orderBy([
            OrderingTerm(expression: countExpr, mode: OrderingMode.desc),
          ]))
        .get();
    final adultRe = RegExp(r'adult|erotic|xxx|porn|dorcel|brazzers',
        caseSensitive: false);
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (out.length >= limit) break;
      final cat = r.readTable(_db.categories);
      final n = r.read(countExpr) ?? 0;
      if (n <= 0) continue;
      if (adultRe.hasMatch(cat.name)) continue;
      out.add({'name': cat.name, 'type': cat.type, 'count': n});
    }
    return out;
  }

  /// Find every movie/series in the library whose cast OR director
  /// metadata mentions [personName]. Used by the cast-deep-dive
  /// sheet — tap an actor, see their other appearances in your
  /// catalogue.
  ///
  /// Pushes the LIKE filter down into SQL so a 30k-row catalogue
  /// stays a sub-second query rather than the all-fetch-then-filter
  /// pattern the first iteration used. Live TV is excluded — it
  /// doesn't carry person metadata. Hidden categories are filtered
  /// out the same way the rest of the search does.
  Future<List<Channel>> searchChannelsByCastMember(
    String personName, {
    int limit = 30,
  }) async {
    final trimmed = personName.trim();
    if (trimmed.isEmpty) return const [];
    // Use a parameterised LIKE pattern. Drift exposes `like` on
    // text columns which lowers to SQL `LIKE` — SQLite's LIKE is
    // case-insensitive for ASCII but not for full Unicode; that's
    // acceptable here since person names are ASCII-dominant.
    // Wrap with %…% for substring matching.
    final pattern = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
          _db.categories.id.equalsExp(_db.channels.categoryId) &
              _db.categories.type.equalsExp(_db.channels.type)),
    ])
          ..where(_db.channels.type.equals('movie') |
              _db.channels.type.equals('series'))
          ..where(_db.categories.isHidden.equals(false))
          ..where(_db.channels.cast.like(pattern) |
              _db.channels.director.like(pattern))
          ..limit(limit))
        .get();
    return rows.map((row) => row.readTable(_db.channels)).toList();
  }

  /// Search channels by name filtered by type (movie/series/live).
  /// Filters out channels from hidden categories.
  /// Type-scoped variant of [searchChannels]. Same diacritic-aware
  /// multi-field matching, but limited to one of `movie` / `series`
  /// / `live`. The dashboard search screen fires three of these in
  /// parallel so each section gets its own bounded result list.
  ///
  /// Two-pass strategy: first an exact substring match; if that
  /// returns nothing, fall back to a 1-edit Levenshtein fuzzy match
  /// so typos like `tarkovsiy` / `intersttellar` still surface
  /// results without waiting for the AI tier.
  Future<List<Channel>> searchChannelsByType(String query, String type, {int limit = 100}) async {
    final tokens = SearchNormalizer.tokens(query);
    if (tokens.isEmpty) return const [];
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
    ).get();

    // Build (channel, haystack) tuples once so the fuzzy pass below
    // doesn't re-normalise. The list is bounded by the type filter
    // and hidden-category exclusion; for the user's catalogue this
    // is a few thousand entries at most. Enrichment is overlaid first
    // so a genre query ("korku") matches items whose provider genre
    // was empty, and the returned channel carries the inferred genre.
    final enrich = await _loadEnrichmentMap();
    final pairs = rows.map((row) {
      final ch = _applyEnrichment(row.readTable(_db.channels), enrich);
      final cat = row.readTable(_db.categories);
      return (ch: ch, haystack: _buildHaystack(ch, cat));
    }).toList();

    // Pass 1: exact substring AND match.
    final out = <Channel>[];
    for (final p in pairs) {
      if (out.length >= limit) break;
      if (SearchNormalizer.matches(p.haystack, tokens)) {
        out.add(p.ch);
      }
    }
    if (out.isNotEmpty) return out;

    // Pass 2: fuzzy fallback. Only runs when the strict pass found
    // nothing — typos shouldn't crowd out correct hits.
    for (final p in pairs) {
      if (out.length >= limit) break;
      if (SearchNormalizer.matchesFuzzy(p.haystack, tokens)) {
        out.add(p.ch);
      }
    }
    return out;
  }

  /// Canonical English ↔ Turkish bilingual genre synonyms.
  ///
  /// Keyed by either side — `expand(["horror"])` returns both
  /// "horror" and "korku", and `expand(["korku"])` returns the same
  /// pair. This is the cheap belt-and-suspenders fix for the
  /// AI-emits-English-only-but-catalog-is-Turkish mismatch; the
  /// system prompt already asks Gemini to emit bilingual genre
  /// lists, this just covers the case where it doesn't.
  static const Map<String, List<String>> _genreSynonyms = {
    'horror': ['horror', 'korku'],
    'korku': ['korku', 'horror'],
    'action': ['action', 'aksiyon'],
    'aksiyon': ['aksiyon', 'action'],
    'comedy': ['comedy', 'komedi'],
    'komedi': ['komedi', 'comedy'],
    'crime': ['crime', 'polisiye', 'polis', 'suç'],
    'polisiye': ['polisiye', 'crime', 'polis'],
    'thriller': ['thriller', 'gerilim'],
    'gerilim': ['gerilim', 'thriller'],
    'romance': ['romance', 'romantik', 'romantizm'],
    'romantik': ['romantik', 'romance'],
    'sci-fi': ['sci-fi', 'science fiction', 'bilim kurgu', 'bilimkurgu'],
    'bilim kurgu': ['bilim kurgu', 'sci-fi', 'science fiction'],
    'documentary': ['documentary', 'belgesel'],
    'belgesel': ['belgesel', 'documentary'],
    'drama': ['drama'],
    'family': ['family', 'aile'],
    'aile': ['aile', 'family'],
    'fantasy': ['fantasy', 'fantastik', 'fantezi'],
    'fantastik': ['fantastik', 'fantasy'],
    'animation': ['animation', 'animasyon', 'çizgi film'],
    'animasyon': ['animasyon', 'animation'],
    'war': ['war', 'savaş'],
    'savaş': ['savaş', 'war'],
    'history': ['history', 'tarih', 'tarihi'],
    'tarih': ['tarih', 'history'],
    'mystery': ['mystery', 'gizem', 'esrarengiz'],
    'gizem': ['gizem', 'mystery'],
    'adventure': ['adventure', 'macera'],
    'macera': ['macera', 'adventure'],
    'biography': ['biography', 'biyografi'],
    'biyografi': ['biyografi', 'biography'],
    'music': ['music', 'müzik'],
    'müzik': ['müzik', 'music'],
    'sport': ['sport', 'spor'],
    'spor': ['spor', 'sport'],
    'western': ['western', 'kovboy'],
    'kovboy': ['kovboy', 'western'],
  };

  /// Expand a genre list using [_genreSynonyms], deduping. Pass-through
  /// for tokens not in the map (e.g. obscure or custom genres).
  static List<String>? _expandGenreSynonyms(List<String>? input) {
    if (input == null || input.isEmpty) return input;
    final out = <String>{};
    for (final g in input) {
      final synonyms = _genreSynonyms[g];
      if (synonyms != null) {
        out.addAll(synonyms);
      } else {
        out.add(g);
      }
    }
    return out.toList();
  }

  /// Search powered by a [SearchIntent] from Gemini.
  ///
  /// Every field on the intent is optional; missing fields don't
  /// constrain the result set. Filters are applied as follows:
  ///
  /// * `contentType` → strict equality on `channels.type`
  /// * `genres` → case-insensitive substring match against the
  ///    comma-separated `channels.genre` column. ANY of the supplied
  ///    genres counts as a hit (OR semantics), so "romantik komedi"
  ///    matches rows tagged with either "Romance" or "Comedy".
  /// * `minYear` / `maxYear` → numeric parse of `channels.year`
  ///    (it's nullable text). Rows with unparseable years are
  ///    excluded only when a year filter is requested.
  /// * `minRating` → numeric compare against `channels.rating`
  ///    (nullable double). Rows with no rating are excluded only
  ///    when a rating threshold is set.
  /// * `keywords` → multi-column case-insensitive substring across
  ///    name + plot + cast + director.
  ///
  /// We load the candidate rows in SQL (cheap, single join), then
  /// apply Dart-side predicates for the fuzzy comma-separated /
  /// case-insensitive bits. SQLite LIKE is ASCII-only for case
  /// folding, which doesn't play well with Turkish characters —
  /// matching in Dart sidesteps that.
  Future<List<Channel>> searchChannelsByIntent(
    SearchIntent intent, {
    int limit = 100,
  }) async {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])..where(_db.categories.isHidden.equals(false));

    if (intent.contentType != null) {
      query.where(_db.channels.type.equals(intent.contentType!));
    }

    final rows = await query.get();
    final channels = rows.map((row) => row.readTable(_db.channels));

    final keywordsLower = intent.keywords?.trim().toLowerCase();
    // Bilingual genre matching — Xtream catalogs are notorious for
    // shipping Turkish genre labels ("Korku, Gerilim") even though
    // the rest of the metadata is in English. The AI is asked to
    // emit both languages, but we expand again defensively so an
    // English-only `["horror"]` from older prompt versions still
    // matches a "Korku" channel and vice-versa.
    final genres = _expandGenreSynonyms(
      intent.genres
          ?.map((g) => g.trim().toLowerCase())
          .where((g) => g.isNotEmpty)
          .toList(),
    );
    final castLower = intent.castContains?.trim().toLowerCase();
    final directorLower = intent.directorContains?.trim().toLowerCase();
    // Theme keywords matched OR-wise — any hit qualifies. Lower-cased
    // once here so the inner predicate doesn't re-allocate per channel.
    final themes = intent.themeKeywords
        ?.map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();

    final filtered = channels.where((ch) {
      // Keywords: substring across name/plot/cast/director.
      if (keywordsLower != null && keywordsLower.isNotEmpty) {
        final haystack = [
          ch.name,
          ch.plot ?? '',
          ch.cast ?? '',
          ch.director ?? '',
        ].join('  ').toLowerCase();
        if (!haystack.contains(keywordsLower)) return false;
      }

      // Genres: any-match against the comma-separated genre column.
      if (genres != null && genres.isNotEmpty) {
        final g = (ch.genre ?? '').toLowerCase();
        if (g.isEmpty) return false;
        final hit = genres.any((wanted) => g.contains(wanted));
        if (!hit) return false;
      }

      // Year range.
      if (intent.minYear != null || intent.maxYear != null) {
        final y = int.tryParse(ch.year ?? '');
        if (y == null) return false;
        if (intent.minYear != null && y < intent.minYear!) return false;
        if (intent.maxYear != null && y > intent.maxYear!) return false;
      }

      // Rating threshold.
      if (intent.minRating != null) {
        final r = ch.rating;
        if (r == null || r < intent.minRating!) return false;
      }

      // Cast contains — case-insensitive substring against the
      // comma-separated cast column. SQL LIKE doesn't fold Turkish
      // characters, so we filter in Dart instead.
      if (castLower != null && castLower.isNotEmpty) {
        final c = (ch.cast ?? '').toLowerCase();
        if (c.isEmpty || !c.contains(castLower)) return false;
      }

      // Director contains — same pattern.
      if (directorLower != null && directorLower.isNotEmpty) {
        final d = (ch.director ?? '').toLowerCase();
        if (d.isEmpty || !d.contains(directorLower)) return false;
      }

      // Theme keywords — OR semantics. Match if any keyword appears
      // in the title or plot. The AI synthesises both user-language
      // and English variants, so a Turkish query still hits an
      // English plot (a common Xtream case).
      if (themes != null && themes.isNotEmpty) {
        final haystack = '${ch.name}  ${ch.plot ?? ""}'.toLowerCase();
        final hit = themes.any((kw) => haystack.contains(kw));
        if (!hit) return false;
      }

      return true;
    });

    return filtered.take(limit).toList();
  }

  /// Full sync: categories + all streams
  Future<void> refreshContent(int accountId) async {
    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncAll(account);
      // syncAll insertOrReplaces categories (resetting isHidden to the
      // default), so re-apply the user's saved visibility prefs.
      await reapplyCategoryPrefs();
    }
  }

  /// Live channels currently broadcasting something — joined with
  /// the Program that is on-air right now. Powers the dashboard /
  /// Live TV "Şu an canlıda" rail.
  ///
  /// Returns up to [limit] channels whose programmes table contains
  /// a row covering `now`. Channels with no EPG entry for the
  /// current slot are excluded (we don't want to render a "now"
  /// rail with empty programme titles). Sorted by program title
  /// alphabetically as a stable default; the UI may re-sort.
  ///
  /// Single-shot, not a stream — the rail invalidates on a minute
  /// timer in the UI rather than re-querying Drift continuously.
  Future<List<({Channel channel, Program program})>> liveNowOnAir({
    int limit = 30,
  }) async {
    final now = DateTime.now();
    // JOIN programs with the channels they reference. Filter to the
    // slot that contains `now`. Limit channels.type to 'live' so we
    // never accidentally surface VOD rows here.
    final rows = await (_db.select(_db.programs).join([
      innerJoin(
        _db.channels,
        _db.channels.streamId.equalsExp(_db.programs.channelId) &
            _db.channels.type.equals('live'),
      ),
      // Respect hidden categories — a hidden live category shouldn't
      // leak into the dashboard "on now" rail.
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where(_db.categories.isHidden.equals(false) &
              _db.programs.start.isSmallerOrEqualValue(now) &
              _db.programs.stop.isBiggerThanValue(now))
          ..orderBy([
            OrderingTerm(
                expression: _db.programs.title,
                mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
    final out = <({Channel channel, Program program})>[];
    final seen = <int>{};
    for (final r in rows) {
      final ch = r.readTable(_db.channels);
      // Deduplicate against channels that have multiple overlapping
      // EPG entries (rare but happens with imported XMLTV feeds).
      if (!seen.add(ch.streamId)) continue;
      out.add((channel: ch, program: r.readTable(_db.programs)));
    }
    return out;
  }

  /// Keyword search over LIVE channels only — for the agent's
  /// "open the news channel" / "CNN'i aç" style requests. Live
  /// channels carry no embeddings, so this stays plain-text.
  Future<List<Channel>> searchLiveChannels(String query, {int limit = 20}) async {
    final tokens = SearchNormalizer.tokens(query);
    if (tokens.isEmpty) return const [];
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals('live'))
      ..where(_db.categories.isHidden.equals(false))
    ).get();
    final out = <Channel>[];
    for (final r in rows) {
      if (out.length >= limit) break;
      final ch = r.readTable(_db.channels);
      final cat = r.readTableOrNull(_db.categories);
      if (SearchNormalizer.matches(_buildHaystack(ch, cat), tokens)) {
        out.add(ch);
      }
    }
    return out;
  }

  /// Upcoming EPG programmes whose title matches [query], starting now
  /// or later, within [withinHours]. Powers the agent's "when's the
  /// match / remind me about X" flows — each row carries the channel
  /// plus the programme's start/stop so a reminder epoch is derivable.
  Future<List<({Channel channel, Program program})>> searchUpcomingPrograms(
    String query, {
    int withinHours = 168,
    int limit = 20,
  }) async {
    final tokens = SearchNormalizer.tokens(query);
    if (tokens.isEmpty) return const [];
    final now = DateTime.now();
    final until = now.add(Duration(hours: withinHours));
    final rows = await (_db.select(_db.programs).join([
      innerJoin(
        _db.channels,
        _db.channels.streamId.equalsExp(_db.programs.channelId) &
            _db.channels.type.equals('live'),
      ),
    ])
          ..where(_db.programs.stop.isBiggerThanValue(now) &
              _db.programs.start.isSmallerThanValue(until))
          ..orderBy([
            OrderingTerm(
                expression: _db.programs.start, mode: OrderingMode.asc),
          ])
          ..limit(2000))
        .get();
    final out = <({Channel channel, Program program})>[];
    for (final r in rows) {
      if (out.length >= limit) break;
      final prog = r.readTable(_db.programs);
      final hay = SearchNormalizer.normalise(
          '${prog.title} ${prog.description ?? ''}');
      if (SearchNormalizer.matches(hay, tokens)) {
        out.add((channel: r.readTable(_db.channels), program: prog));
      }
    }
    return out;
  }

  Stream<List<Program>> watchPrograms(int channelId) {
    final now = DateTime.now();
    return (_db.select(_db.programs)
      ..where((tbl) => tbl.channelId.equals(channelId))
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.start)])
    ).watch();
  }

  /// Check if enough time has passed since last EPG sync.
  ///
  /// Returns `true` (i.e. "needs sync") on any SharedPreferences error
  /// so we don't accidentally throttle the user out of EPG forever if
  /// prefs are wedged. Logged in debug so a real platform-channel
  /// failure is at least visible.
  Future<bool> _shouldSyncEpg() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt(_epgSyncKey) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastSync;
      return elapsed > _epgSyncInterval.inMilliseconds;
    } catch (e, st) {
      debugPrint('[ContentRepo] _shouldSyncEpg prefs read failed: $e\n$st');
      return true;
    }
  }

  /// Mark that an EPG sync just completed. Swallows write failures —
  /// next call to [_shouldSyncEpg] will just re-sync, no permanent
  /// state corruption — but logs them so they're not invisible.
  Future<void> _markEpgSynced() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_epgSyncKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[ContentRepo] _markEpgSynced prefs write failed: $e');
    }
  }

  /// Check if DB has any EPG programs for live channels
  Future<bool> hasEpgData() async {
    final now = DateTime.now();
    final count = await (_db.select(_db.programs)
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..limit(1)
    ).get();
    return count.isNotEmpty;
  }

  /// Sync single channel EPG - only if no data exists in DB.
  /// Uses Xtream API first, then XMLTV fallback.
  Future<void> syncChannelEpg(int accountId, String streamId) async {
    // Check if we already have future programs for this channel
    final channelId = int.tryParse(streamId) ?? 0;
    final now = DateTime.now();
    final existing = await (_db.select(_db.programs)
      ..where((tbl) => tbl.channelId.equals(channelId))
      ..where((tbl) => tbl.stop.isBiggerThanValue(now))
      ..limit(1)
    ).get();
    if (existing.isNotEmpty) return; // Already have data, skip API call

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account == null) return;

    if (account.type == 'xtream') {
      await _syncService.syncEpg(account, streamId);

      // Check if Xtream EPG returned data
      final afterXtream = await (_db.select(_db.programs)
        ..where((tbl) => tbl.channelId.equals(channelId))
        ..where((tbl) => tbl.stop.isBiggerThanValue(now))
        ..limit(1)
      ).get();
      if (afterXtream.isNotEmpty) return; // Xtream worked
    }

    // XMLTV fallback
    await _syncService.syncChannelEpgFromXmltv(accountId, channelId);
  }

  /// Sync EPG for all live channels - throttled (max once per 2 hours)
  /// If DB already has data, shows that immediately and syncs silently in background.
  Future<void> syncAllLiveEpg(int accountId) async {
    // Check if we should sync at all
    final shouldSync = await _shouldSyncEpg();
    if (!shouldSync) return; // Recently synced, use DB cache

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncAllLiveEpg(account);
      await _markEpgSynced();
    }
  }

  /// Sync EPG for specific channel IDs (batch) - throttled
  Future<void> syncEpgBatch(int accountId, List<int> streamIds) async {
    final shouldSync = await _shouldSyncEpg();
    if (!shouldSync) return;

    final account = await (_db.select(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).getSingleOrNull();
    if (account != null) {
      await _syncService.syncEpgBatch(account, streamIds);
      await _markEpgSynced();
    }
  }

  /// Delete expired program data (cleanup)
  Future<void> cleanupOldPrograms() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));
    await (_db.delete(_db.programs)
      ..where((tbl) => tbl.stop.isSmallerThanValue(cutoff))
    ).go();
  }

  /// Update channel metadata (backdrop, trailer, genre, plot, etc.) from detail API
  Future<void> updateChannelMetadata(
    int streamId,
    String type, {
    String? backdropPath,
    String? youtubeTrailer,
    String? genre,
    String? plot,
    String? director,
    String? castInfo,
  }) async {
    if (backdropPath == null && youtubeTrailer == null &&
        genre == null && plot == null && director == null && castInfo == null) {
      return;
    }
    await (_db.update(_db.channels)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).write(ChannelsCompanion(
      backdropPath: backdropPath != null ? Value(backdropPath) : const Value.absent(),
      youtubeTrailer: youtubeTrailer != null ? Value(youtubeTrailer) : const Value.absent(),
      genre: genre != null ? Value(genre) : const Value.absent(),
      plot: plot != null ? Value(plot) : const Value.absent(),
      director: director != null ? Value(director) : const Value.absent(),
      cast: castInfo != null ? Value(castInfo) : const Value.absent(),
    ));
  }

  /// Return a small stratified sample of the library for AI context.
  ///
  /// Used by the "what should I watch tonight?" chat — Gemini needs
  /// to know *what's available* before it can recommend anything, but
  /// shoving a 10K-item library into the prompt is wasteful (cost,
  /// latency, attention). We pick the highest-rated rows per type so
  /// the AI sees a representative cross-section without paging the
  /// whole catalogue.
  ///
  /// Hidden categories are excluded — anything the user has chosen
  /// to hide shouldn't surface as an AI recommendation either.
  Future<List<Channel>> sampleLibraryForAi({
    int moviesPerType = 30,
    int seriesPerType = 30,
    int livePerType = 20,
  }) async {
    Future<List<Channel>> topByType(String type, int limit) async {
      final rows = await (_db.select(_db.channels).join([
        innerJoin(
          _db.categories,
          _db.categories.id.equalsExp(_db.channels.categoryId) &
              _db.categories.type.equalsExp(_db.channels.type),
        ),
      ])
            ..where(_db.channels.type.equals(type))
            ..where(_db.categories.isHidden.equals(false))
            ..orderBy([
              // Highest-rated first; tie-break on most recently added
              // (the `added` column is a timestamp string from the
              // Xtream API).
              OrderingTerm(
                  expression: _db.channels.rating,
                  mode: OrderingMode.desc),
              OrderingTerm(
                  expression: _db.channels.added,
                  mode: OrderingMode.desc),
            ])
            ..limit(limit))
          .get();
      return rows.map((row) => row.readTable(_db.channels)).toList();
    }

    final results = await Future.wait([
      topByType('movie', moviesPerType),
      topByType('series', seriesPerType),
      topByType('live', livePerType),
    ]);
    return _mergeEnrichment([...results[0], ...results[1], ...results[2]]);
  }

  /// Overlay AI catalogue enrichment onto channels whose provider
  /// `genre` / `year` are empty. This is the SINGLE integration point
  /// that lets every AI surface — search, "similar", and the dashboard
  /// rails (Sana Özel, mood, hero, digest), which all build their
  /// candidates through [sampleLibraryForAi] / [recentAdditionsForAi]
  /// — benefit from enrichment without each re-querying the table.
  ///
  /// No-op when nothing needs filling. Loads the whole (small)
  /// enrichment table into a map rather than an `IN (...)` clause —
  /// the id list can run to thousands on a full-library merge, which
  /// would blow past SQLite's bound-variable limit.
  Future<List<Channel>> _mergeEnrichment(List<Channel> channels) async {
    final needsAny =
        channels.any((c) => c.genre == null || c.genre!.isEmpty);
    if (!needsAny) return channels;
    final map = await _loadEnrichmentMap();
    if (map.isEmpty) return channels;
    return [for (final c in channels) _applyEnrichment(c, map)];
  }

  /// Full enrichment table as a `"streamId|type"` → row map. The table
  /// only holds enriched items, so it's bounded and cheap to read.
  Future<Map<String, ContentEnrichmentData>> _loadEnrichmentMap() async {
    final rows = await _db.select(_db.contentEnrichment).get();
    return {for (final r in rows) '${r.streamId}|${r.type}': r};
  }

  /// Overlay enrichment onto a single channel when its provider
  /// `genre` / `year` are empty. Pure — takes a preloaded map so it's
  /// cheap to call in a tight loop (search) or a list comprehension.
  Channel _applyEnrichment(
      Channel c, Map<String, ContentEnrichmentData> map) {
    if (c.genre != null && c.genre!.isNotEmpty) return c;
    final e = map['${c.streamId}|${c.type}'];
    if (e == null) return c;
    return c.copyWith(
      genre: Value(e.genres),
      year: Value((c.year != null && c.year!.isNotEmpty)
          ? c.year
          : e.year?.toString()),
    );
  }

  /// Freshest VOD by the Xtream `added` timestamp, newest first.
  ///
  /// [sampleLibraryForAi] orders by rating, so brand-new titles —
  /// which usually carry no rating yet — sink to the bottom and never
  /// reach the AI's prompt. The chat assistant then insists "yeni film
  /// yok" even right after a catalogue refresh. This method gives the
  /// chat a dedicated recency pool so "what's new?" actually works.
  ///
  /// `added` is a text-typed Unix-epoch string from the provider, so
  /// we can't ORDER BY it in SQL meaningfully (lexical vs numeric).
  /// We pull a bounded slice and sort numerically in Dart — the same
  /// approach the hero billboard uses.
  Future<List<Channel>> recentAdditionsForAi({int limit = 40}) async {
    final rows = await (_db.select(_db.channels).join([
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
          ..where((_db.channels.type.equals('movie') |
                  _db.channels.type.equals('series')) &
              _db.categories.isHidden.equals(false))
          ..limit(3000))
        .get();
    int parseAdded(Channel c) => int.tryParse(c.added?.trim() ?? '') ?? 0;
    final all = rows.map((r) => r.readTable(_db.channels)).toList()
      ..sort((a, b) => parseAdded(b).compareTo(parseAdded(a)));
    // Drop rows with no `added` value at all — a zero timestamp isn't
    // "recent", it's "unknown", and surfacing it as new would be a lie.
    final recent = all.where((c) => parseAdded(c) > 0).take(limit).toList();
    return _mergeEnrichment(recent);
  }

  /// Watch channels that have playback progress (continue watching).
  /// Scoped to the active profile so the rail isolates per-person
  /// state — the kids' half-watched cartoons don't leak into the
  /// parent's continue-watching.
  Stream<List<Channel>> watchContinueWatching(String type) {
    final pid = _pid;
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
      ..where(_db.playbackProgress.profileId.equals(pid))
      ..orderBy([OrderingTerm(expression: _db.playbackProgress.updatedAt, mode: OrderingMode.desc)])
      ..limit(50);

    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Watch all continue watching items (movies + series combined,
  /// sorted by updatedAt), scoped to the active profile.
  Stream<List<Channel>> watchAllContinueWatching() {
    final pid = _pid;
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
      innerJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
            _db.categories.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.isIn(['movie', 'series']))
      ..where(_db.categories.isHidden.equals(false))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
      ..where(_db.playbackProgress.profileId.equals(pid))
      ..orderBy([OrderingTerm(expression: _db.playbackProgress.updatedAt, mode: OrderingMode.desc)])
      ..limit(20);

    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Watch playback progress for a specific channel
  Stream<PlaybackProgressData?> watchPlaybackProgress(int streamId, String type) {
    return (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).watchSingleOrNull();
  }

  /// Get playback progress for a specific channel (one-shot)
  Future<PlaybackProgressData?> getPlaybackProgress(int streamId, String type) {
    return (_db.select(_db.playbackProgress)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.type.equals(type))
    ).getSingleOrNull();
  }

  /// Watch channels with their playback progress (for history display)
  Stream<List<Channel>> watchFavoriteChannels(String type, List<int> streamIds) {
    if (streamIds.isEmpty) return Stream.value([]);
    return (_db.select(_db.channels)
      ..where((tbl) => tbl.streamId.isIn(streamIds) & tbl.type.equals(type))
    ).watch();
  }

  /// Check if a series has new episodes
  Stream<SeriesTrackingData?> watchSeriesTracking(int seriesId) {
    return (_db.select(_db.seriesTracking)
      ..where((tbl) => tbl.seriesId.equals(seriesId))
    ).watchSingleOrNull();
  }

  /// Get all series with new episodes (for badges/notifications)
  Stream<List<SeriesTrackingData>> watchSeriesWithNewEpisodes() {
    return (_db.select(_db.seriesTracking)
      ..where((tbl) => tbl.hasNewEpisodes.equals(true))
    ).watch();
  }

  /// Mark new episodes as seen (user opened the series)
  Future<void> markNewEpisodesSeen(int seriesId) async {
    await (_db.update(_db.seriesTracking)
      ..where((tbl) => tbl.seriesId.equals(seriesId))
    ).write(const SeriesTrackingCompanion(
      hasNewEpisodes: Value(false),
      newEpisodeCount: Value(0),
    ));
  }
}

@riverpod
ContentRepository contentRepository(Ref ref) {
  // Bump on profile switch so the cached repo gets rebuilt and
  // every per-profile query reflects the new id.
  ref.watch(activeProfileIdProvider);
  return ContentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncServiceProvider),
    () => ref.read(activeProfileIdProvider).value ?? 1,
  );
}
