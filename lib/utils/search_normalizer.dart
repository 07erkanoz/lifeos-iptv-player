/// Turkish-aware text normalisation for free-text catalogue search.
///
/// The library has a couple of bilingual hot-spots — Turkish channel
/// names with `İ / ş / ğ / ç / ü / ö / ı`, English titles users type
/// in ASCII, French/Spanish movie titles with `é / à / ñ`, etc. The
/// stock `String.toLowerCase()` only folds ASCII case correctly:
/// it leaves `İ` as `i̇` (combining dot above) instead of `i`, and
/// doesn't strip diacritics at all. Result: searching `interstellar`
/// fails to match `İnterstellar`, and searching `simarik` fails to
/// match `Şımarık`.
///
/// This helper normalises both sides of the search comparison so they
/// converge on a stable ASCII representation:
///
///   * `İ` → `i`, `I` → `i` (Turkish locale produces `ı` lower-case
///     for `I`, which is not what searchers expect when they paste a
///     Latin name)
///   * `ş ğ ç ü ö ı` → `s g c u o i`
///   * Common Latin diacritics (`é à ä ñ ô`, …) → bare letter
///   * Run-of-the-mill ASCII downcase
///   * Whitespace collapsed, leading / trailing trimmed
///
/// We deliberately keep this in Dart rather than push to SQL — SQLite
/// `LOWER()` is ASCII-only and writing a `REPLACE(REPLACE(REPLACE(…))
/// `chain` per query string would be both unreadable and unindexable.
/// The repository call sites pull a bounded slice (5–10 k rows) and
/// filter in Dart, which on the user's 30 k-row catalogue still
/// completes in <50 ms.
class SearchNormalizer {
  const SearchNormalizer._();

  /// Direct character map. Source = single code point we want to
  /// fold, target = the ASCII letter (or letters) it folds to.
  ///
  /// Order matters only for multi-codepoint sources (none here today;
  /// `İ` is a single code point even though it visually has the dot
  /// — we never see the decomposed `i + COMBINING_DOT_ABOVE` form in
  /// practice because Dart strings preserve precomposed forms).
  static const _foldMap = <String, String>{
    // Turkish
    'İ': 'i', 'ı': 'i',
    'Ş': 's', 'ş': 's',
    'Ğ': 'g', 'ğ': 'g',
    'Ç': 'c', 'ç': 'c',
    'Ü': 'u', 'ü': 'u',
    'Ö': 'o', 'ö': 'o',
    // Common Latin diacritics — covers French, Spanish, Portuguese,
    // German vowel-only sets. We don't fold sharp-s (`ß`) because
    // some German titles intentionally use it.
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'Á': 'a', 'À': 'a', 'Â': 'a', 'Ä': 'a', 'Ã': 'a', 'Å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'É': 'e', 'È': 'e', 'Ê': 'e', 'Ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'Í': 'i', 'Ì': 'i', 'Î': 'i', 'Ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o',
    'Ó': 'o', 'Ò': 'o', 'Ô': 'o', 'Õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u',
    'Ú': 'u', 'Ù': 'u', 'Û': 'u',
    'ñ': 'n', 'Ñ': 'n',
    'ý': 'y', 'ÿ': 'y',
    'Ý': 'y',
  };

  /// Normalise a single search string for both query side and
  /// haystack side. Idempotent — calling it twice is safe.
  ///
  /// Returns lower-case ASCII with whitespace collapsed.
  static String normalise(String input) {
    if (input.isEmpty) return '';
    // 1. Apply the fold map BEFORE toLowerCase so Turkish `İ` (which
    //    `toLowerCase()` turns into `i̇` under the default locale) is
    //    handled by the explicit map first.
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final folded = _foldMap[ch];
      buf.write(folded ?? ch);
    }
    // 2. ASCII downcase.
    var s = buf.toString().toLowerCase();
    // 3. Collapse runs of whitespace.
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Split a normalised query into individual word tokens for AND
  /// matching. Drops sub-three-char tokens so a user typing `matt`
  /// doesn't get every haystack entry containing a stray short word.
  /// Single-token queries (e.g. just `interstellar`) are preserved
  /// regardless of length.
  static List<String> tokens(String query) {
    final n = normalise(query);
    if (n.isEmpty) return const [];
    final parts = n.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.length <= 1) return parts;
    return parts.where((w) => w.length >= 3).toList();
  }

  /// True when every [queryTokens] entry appears as a substring of
  /// [haystack]. [haystack] should already have been normalised.
  /// This is the multi-word AND match: searching "matthew
  /// interstellar" finds an entry whose title is "Interstellar" and
  /// whose cast is "Matthew McConaughey, …" because both tokens hit
  /// the joined haystack, even though they live in different
  /// columns.
  static bool matches(String haystack, List<String> queryTokens) {
    if (queryTokens.isEmpty) return false;
    for (final t in queryTokens) {
      if (!haystack.contains(t)) return false;
    }
    return true;
  }

  /// Fuzzy variant of [matches]: every query token must either appear
  /// as a substring (exact match) OR be within Levenshtein distance
  /// [maxDistance] of some word in the haystack. Used as a fallback
  /// when the strict [matches] returns no hits — covers user typos
  /// like "tarkovsiy" → "tarkovsky", "intersttellar" → "interstellar".
  ///
  /// Cost-aware: distance computation is O(|q|·|w|), and the haystack
  /// has dozens of words. We bail early for any token that already
  /// substring-matches and only run Levenshtein on the misses. Tokens
  /// shorter than 4 chars are skipped from fuzzy matching (a 1-edit
  /// distance to "ali" matches half the alphabet) — short tokens
  /// must hit exactly.
  static bool matchesFuzzy(
    String haystack,
    List<String> queryTokens, {
    int maxDistance = 1,
  }) {
    if (queryTokens.isEmpty) return false;
    final words = haystack.split(' ');
    for (final t in queryTokens) {
      if (haystack.contains(t)) continue; // fast path
      if (t.length < 4) return false; // no fuzzy on short tokens
      bool fuzzyHit = false;
      for (final w in words) {
        // Skip wildly different lengths early — a 6-char token can't
        // be within 1 edit of a 10-char word.
        if ((w.length - t.length).abs() > maxDistance) continue;
        if (_levenshtein(t, w) <= maxDistance) {
          fuzzyHit = true;
          break;
        }
      }
      if (!fuzzyHit) return false;
    }
    return true;
  }

  /// Classic Levenshtein edit distance via the two-row DP. Returns
  /// the minimum number of single-character edits (insertions,
  /// deletions, substitutions) to turn [a] into [b].
  ///
  /// Bounded usage: caller only invokes for word pairs of similar
  /// length (<= maxDistance apart), so worst-case input length is
  /// ~12 chars — the 2 × 13 int array is trivial.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins
            ? (del < sub ? del : sub)
            : (ins < sub ? ins : sub);
      }
      // Swap rows for next iteration.
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }
}
