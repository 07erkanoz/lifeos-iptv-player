/// Structured filter parsed from a natural-language search query.
///
/// Returned by `GeminiService.parseSearchQuery`. Every field is
/// nullable — the parser only fills in what it could confidently
/// extract from the user's phrasing, and the search repository
/// treats missing fields as "don't filter on this".
///
/// `keywords` carries the residual free-text after structured
/// filters are pulled out, so a query like
///   "Kore polis dizisi Phantom Lawyer"
/// becomes
///   contentType: 'series', genres: ['crime'], keywords: 'Phantom Lawyer'.
///
/// The structure is intentionally a flat record of primitives so it
/// round-trips through `responseSchema` JSON cleanly and is trivial
/// to unit-test.
class SearchIntent {
  /// Free-text keywords to LIKE-match against name/plot/cast/etc.
  /// Null when the user's phrasing was *purely* filter-shaped
  /// (e.g. "kısa polis filmi" → no keywords, only filters).
  final String? keywords;

  /// One of 'movie', 'series', 'live'. Null = search all types.
  final String? contentType;

  /// Lowercase English genre names (e.g. 'crime', 'action',
  /// 'romance'). Multiple → OR'd in the search. Null/empty = no
  /// genre filter.
  final List<String>? genres;

  final int? minYear;
  final int? maxYear;

  /// Inclusive minimum rating (0..10).
  final double? minRating;

  /// Substring to look for in `Channel.cast`. Used when the user
  /// types "Yoo Yeon-seok filmleri" / "Tom Hanks" / etc. We accept
  /// the raw human name — the repository does case-insensitive
  /// substring match against the comma-separated cast column.
  final String? castContains;

  /// Same shape as [castContains] but against `Channel.director`.
  /// "Bong Joon-ho yönetmenliği" → directorContains: "Bong Joon-ho".
  final String? directorContains;

  /// Theme / topic keywords supplied multilingually so we catch
  /// content tagged in either the user's language *or* English.
  ///
  /// "dünyanın sonu konulu film" should parse to something like
  ///   themeKeywords: ["dünya sonu", "kıyamet",
  ///                   "apocalypse", "post-apocalyptic"]
  /// and the repository matches against `plot` + `name` with OR
  /// semantics (any keyword hit qualifies). Gemini synthesises the
  /// alternate-language synonyms because Xtream plots are routinely
  /// in mixed languages.
  final List<String>? themeKeywords;

  const SearchIntent({
    this.keywords,
    this.contentType,
    this.genres,
    this.minYear,
    this.maxYear,
    this.minRating,
    this.castContains,
    this.directorContains,
    this.themeKeywords,
  });

  /// True when every filter field is null/empty. The search screen
  /// falls back to plain keyword search in that case — there's no
  /// point routing through the AI codepath if it produced nothing.
  bool get isEmpty =>
      (keywords == null || keywords!.trim().isEmpty) &&
      contentType == null &&
      (genres == null || genres!.isEmpty) &&
      minYear == null &&
      maxYear == null &&
      minRating == null &&
      (castContains == null || castContains!.trim().isEmpty) &&
      (directorContains == null || directorContains!.trim().isEmpty) &&
      (themeKeywords == null || themeKeywords!.isEmpty);

  bool get hasStructuredFilters =>
      contentType != null ||
      (genres != null && genres!.isNotEmpty) ||
      minYear != null ||
      maxYear != null ||
      minRating != null ||
      (castContains != null && castContains!.trim().isNotEmpty) ||
      (directorContains != null && directorContains!.trim().isNotEmpty) ||
      (themeKeywords != null && themeKeywords!.isNotEmpty);

  /// Parse JSON shaped like
  /// `{"keywords": "...", "contentType": "movie", "genres": [...],
  ///   "minYear": 2020, "maxYear": 2024, "minRating": 7.0}`.
  ///
  /// All branches are defensive — missing keys, wrong types, and
  /// stringified numbers (which Gemini sometimes emits despite the
  /// schema) are coerced or dropped silently rather than throwing.
  /// The caller decides what to do with the resulting `SearchIntent`;
  /// it never throws.
  factory SearchIntent.fromJson(Map<String, dynamic> json) {
    String? readString(String key) {
      final v = json[key];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    int? readInt(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? readDouble(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    List<String>? readStringList(String key) {
      final v = json[key];
      if (v is! List) return null;
      final list = v
          .map((e) => e?.toString().trim().toLowerCase() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return list.isEmpty ? null : list;
    }

    // Theme keywords are read with the same defensive list helper
    // as genres but *without* lower-casing — a cast / theme value
    // like "Yoo Yeon-seok" needs to keep its capitalisation for
    // legibility on the AI-explainer chips.
    List<String>? readKeywordList(String key) {
      final v = json[key];
      if (v is! List) return null;
      final list = v
          .map((e) => e?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return list.isEmpty ? null : list;
    }

    final ct = readString('contentType')?.toLowerCase();
    return SearchIntent(
      keywords: readString('keywords'),
      contentType: (ct == 'movie' || ct == 'series' || ct == 'live') ? ct : null,
      genres: readStringList('genres'),
      minYear: readInt('minYear'),
      maxYear: readInt('maxYear'),
      minRating: readDouble('minRating'),
      castContains: readString('castContains'),
      directorContains: readString('directorContains'),
      themeKeywords: readKeywordList('themeKeywords'),
    );
  }

  @override
  String toString() => 'SearchIntent('
      'keywords: $keywords, '
      'contentType: $contentType, '
      'genres: $genres, '
      'year: [$minYear..$maxYear], '
      'minRating: $minRating, '
      'cast: $castContains, '
      'director: $directorContains, '
      'themes: $themeKeywords)';
}
