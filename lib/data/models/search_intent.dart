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

  const SearchIntent({
    this.keywords,
    this.contentType,
    this.genres,
    this.minYear,
    this.maxYear,
    this.minRating,
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
      minRating == null;

  bool get hasStructuredFilters =>
      contentType != null ||
      (genres != null && genres!.isNotEmpty) ||
      minYear != null ||
      maxYear != null ||
      minRating != null;

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

    final ct = readString('contentType')?.toLowerCase();
    return SearchIntent(
      keywords: readString('keywords'),
      contentType: (ct == 'movie' || ct == 'series' || ct == 'live') ? ct : null,
      genres: readStringList('genres'),
      minYear: readInt('minYear'),
      maxYear: readInt('maxYear'),
      minRating: readDouble('minRating'),
    );
  }

  @override
  String toString() => 'SearchIntent('
      'keywords: $keywords, '
      'contentType: $contentType, '
      'genres: $genres, '
      'year: [$minYear..$maxYear], '
      'minRating: $minRating)';
}
