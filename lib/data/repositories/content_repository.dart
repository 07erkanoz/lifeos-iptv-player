import 'package:drift/drift.dart';
// `show debugPrint` only, because `package:flutter/foundation.dart`
// re-exports its own `Category` annotation which collides with our
// generated drift `Category` row class.
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/search_intent.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'content_repository.g.dart';

class ContentRepository {
  final AppDatabase _db;
  final SyncService _syncService;

  /// Minimum interval between full EPG syncs (server-friendly)
  static const _epgSyncInterval = Duration(hours: 2);
  static const _epgSyncKey = 'last_epg_sync_timestamp';

  ContentRepository(this._db, this._syncService);

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

  /// Toggle category visibility
  Future<void> toggleCategoryHidden(String categoryId, String type, bool hidden) async {
    await (_db.update(_db.categories)
      ..where((tbl) => tbl.id.equals(categoryId) & tbl.type.equals(type))
    ).write(CategoriesCompanion(isHidden: Value(hidden)));
  }

  Stream<List<Channel>> watchChannels(String categoryId, {String? type}) {
    final query = _db.select(_db.channels)
      ..where((tbl) => tbl.categoryId.equals(categoryId));
    if (type != null) {
      query.where((tbl) => tbl.type.equals(type));
    }
    return query.watch();
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
    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
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
  /// Uses Dart-side filtering for proper Turkish/Unicode case-insensitive search
  /// (SQLite LIKE is only case-insensitive for ASCII characters).
  /// Filters out channels from hidden categories.
  Future<List<Channel>> searchChannels(String query, {int limit = 50}) async {
    final lowerQuery = query.toLowerCase();
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])..where(_db.categories.isHidden.equals(false))).get();
    return rows
        .map((row) => row.readTable(_db.channels))
        .where((ch) => ch.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
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
          ..where(_db.playbackProgress.position.isBiggerThanValue(0))
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
    final tokens = query
        .toLowerCase()
        .replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_chatStopwords.contains(w))
        .toSet();
    if (tokens.isEmpty) return const [];

    // Expand synonyms — both country/language and genre.
    final expanded = <String>{};
    for (final t in tokens) {
      expanded.add(t);
      final cs = _countrySynonyms[t];
      if (cs != null) expanded.addAll(cs);
      final gs = _genreSynonyms[t];
      if (gs != null) expanded.addAll(gs);
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
      final cat = r.readTable(_db.categories);
      final haystack = [
        ch.name,
        cat.name,
        ch.cast ?? '',
        ch.director ?? '',
        ch.genre ?? '',
      ].join(' ').toLowerCase();
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
  Future<List<Channel>> searchChannelsByType(String query, String type, {int limit = 100}) async {
    final lowerQuery = query.toLowerCase();
    final rows = await (_db.select(_db.channels).join([
      innerJoin(_db.categories,
        _db.categories.id.equalsExp(_db.channels.categoryId) &
        _db.categories.type.equalsExp(_db.channels.type)),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.categories.isHidden.equals(false))
    ).get();
    return rows
        .map((row) => row.readTable(_db.channels))
        .where((ch) => ch.name.toLowerCase().contains(lowerQuery))
        .take(limit)
        .toList();
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
    }
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
    return [...results[0], ...results[1], ...results[2]];
  }

  /// Watch channels that have playback progress (continue watching)
  Stream<List<Channel>> watchContinueWatching(String type) {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.equals(type))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
      ..orderBy([OrderingTerm(expression: _db.playbackProgress.updatedAt, mode: OrderingMode.desc)])
      ..limit(50);

    return query.watch().map((rows) =>
      rows.map((row) => row.readTable(_db.channels)).toList(),
    );
  }

  /// Watch all continue watching items (movies + series combined, sorted by updatedAt)
  Stream<List<Channel>> watchAllContinueWatching() {
    final query = _db.select(_db.channels).join([
      innerJoin(
        _db.playbackProgress,
        _db.playbackProgress.streamId.equalsExp(_db.channels.streamId) &
        _db.playbackProgress.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where(_db.channels.type.isIn(['movie', 'series']))
      ..where(_db.playbackProgress.isFinished.equals(false))
      ..where(_db.playbackProgress.position.isBiggerThanValue(0))
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
  return ContentRepository(ref.watch(appDatabaseProvider), ref.watch(syncServiceProvider));
}
