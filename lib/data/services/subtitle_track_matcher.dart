/// Pure track-matching helpers for restoring the user's last chosen
/// subtitle across episode changes / channel switches / app restarts.
///
/// Why this exists as a separate module:
/// - The old logic compared `wantLanguage` only against the new
///   track's `language` field, but the remember step fell back to
///   `track.title` when `language` was null. Asymmetric: a track
///   selected via title was never matched on title later, so the
///   user "lost" their subtitle every time they advanced episodes.
/// - SubtitleTrack ids are unstable across Player instances, so
///   index-based matching is unreliable. Language + title is what
///   we have.
/// - Pure inputs → unit-testable; mediates between media_kit's
///   SubtitleTrack and AppSettings without either knowing about
///   the other.
library;

/// Minimal track shape the matcher works with. The player wraps
/// `media_kit.SubtitleTrack` (and AudioTrack) into this so the
/// matcher doesn't depend on media_kit and the test suite can
/// build cases inline.
typedef TrackCandidate = ({String id, String? language, String? title});

/// Synthetic ids media_kit uses for "auto" pick and "off". These
/// are never user-meaningful selections we want to restore.
const _syntheticIds = {'auto', 'no'};

/// Map any common language code or English/native name to a canonical
/// ISO 639-2/T 3-letter code. Lets us match a stored "tr" against a
/// new track tagged "tur", or "Türkçe" against "tur", etc. We canonicalize
/// both sides before comparing.
const _languageAliases = <String, String>{
  // Turkish
  'tr': 'tur', 'tur': 'tur', 'turkish': 'tur', 'türkçe': 'tur', 'turkce': 'tur',
  // English
  'en': 'eng', 'eng': 'eng', 'english': 'eng', 'ingilizce': 'eng',
  // French
  'fr': 'fra', 'fra': 'fra', 'fre': 'fra', 'french': 'fra', 'français': 'fra', 'francais': 'fra',
  // German
  'de': 'deu', 'deu': 'deu', 'ger': 'deu', 'german': 'deu', 'deutsch': 'deu', 'almanca': 'deu',
  // Spanish
  'es': 'spa', 'spa': 'spa', 'spanish': 'spa', 'español': 'spa', 'espanol': 'spa',
  // Italian
  'it': 'ita', 'ita': 'ita', 'italian': 'ita', 'italiano': 'ita',
  // Russian
  'ru': 'rus', 'rus': 'rus', 'russian': 'rus', 'русский': 'rus',
  // Arabic
  'ar': 'ara', 'ara': 'ara', 'arabic': 'ara',
  // Japanese
  'ja': 'jpn', 'jpn': 'jpn', 'japanese': 'jpn',
  // Korean
  'ko': 'kor', 'kor': 'kor', 'korean': 'kor',
  // Chinese
  'zh': 'zho', 'zho': 'zho', 'chi': 'zho', 'chinese': 'zho',
  // Portuguese
  'pt': 'por', 'por': 'por', 'portuguese': 'por',
  // Dutch
  'nl': 'nld', 'nld': 'nld', 'dut': 'nld', 'dutch': 'nld',
  // Polish
  'pl': 'pol', 'pol': 'pol', 'polish': 'pol',
  // Swedish
  'sv': 'swe', 'swe': 'swe', 'swedish': 'swe',
  // Norwegian — note the "no" code collides with media_kit's
  // synthetic "off" track id, but we filter those by track.id
  // before this point.
  'no': 'nor', 'nor': 'nor', 'norwegian': 'nor',
  // Danish
  'da': 'dan', 'dan': 'dan', 'danish': 'dan',
  // Finnish
  'fi': 'fin', 'fin': 'fin', 'finnish': 'fin',
  // Greek
  'el': 'ell', 'ell': 'ell', 'gre': 'ell', 'greek': 'ell',
  // Hebrew
  'he': 'heb', 'heb': 'heb', 'hebrew': 'heb',
  // Hindi
  'hi': 'hin', 'hin': 'hin', 'hindi': 'hin',
  // Czech
  'cs': 'ces', 'ces': 'ces', 'cze': 'ces', 'czech': 'ces',
  // Hungarian
  'hu': 'hun', 'hun': 'hun', 'hungarian': 'hun',
  // Romanian
  'ro': 'ron', 'ron': 'ron', 'rum': 'ron', 'romanian': 'ron',
  // Ukrainian
  'uk': 'ukr', 'ukr': 'ukr', 'ukrainian': 'ukr',
};

/// Canonicalize a language string to its ISO 639-2/T code if we know
/// it, otherwise return the trimmed lowercase form. The strip of
/// trailing qualifiers like "(forced)" / "(SDH)" / "[CC]" happens
/// before the lookup so "English (forced)" canonicalizes to "eng".
String _canonicalLanguage(String? raw) {
  if (raw == null) return '';
  var s = raw.trim().toLowerCase();
  // Strip trailing parenthetical / bracketed qualifiers.
  s = s.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]\s*$'), '').trim();
  return _languageAliases[s] ?? s;
}

/// Find the best track in [tracks] for the previously remembered
/// preference [wantLanguage] / [wantTitle]. Returns null if no
/// reasonable match exists; the caller then keeps whatever
/// media_kit defaulted to.
///
/// Match priority (first hit wins):
/// 1. Exact language match (normalized).
/// 2. Exact title match (normalized).
/// 3. Language prefix match in either direction.
/// 4. Title substring match.
/// 5. Title against language / language against title — handles the
///    case where the previous track stored its label in `title` but
///    the new track has the same label in `language`, or vice versa.
TrackCandidate? findBestSubtitleTrack({
  required List<TrackCandidate> tracks,
  String? wantLanguage,
  String? wantTitle,
}) {
  final wantLangCanon = _canonicalLanguage(wantLanguage);
  final wantTitleNorm = _normalize(wantTitle);
  if (wantLangCanon.isEmpty && wantTitleNorm.isEmpty) return null;

  final real = tracks
      .where((t) => !_syntheticIds.contains(t.id))
      .toList(growable: false);
  if (real.isEmpty) return null;

  // 1. Canonical language match. Handles ISO 639-1 ↔ 639-2 (tr↔tur,
  // en↔eng), native names ("Türkçe"↔"tur"), and qualifier stripping
  // ("English (forced)"↔"eng").
  if (wantLangCanon.isNotEmpty) {
    for (final t in real) {
      if (_canonicalLanguage(t.language) == wantLangCanon) return t;
    }
  }
  // 2. Exact title match (normalized — lowercase + trim).
  if (wantTitleNorm.isNotEmpty) {
    for (final t in real) {
      if (_normalize(t.title) == wantTitleNorm) return t;
    }
  }
  // 3. Title substring match. Handles "English" stored vs
  // "English (forced)" available, or any extra qualifier mismatch.
  if (wantTitleNorm.isNotEmpty) {
    for (final t in real) {
      final tt = _normalize(t.title);
      if (tt.isNotEmpty &&
          (tt.contains(wantTitleNorm) || wantTitleNorm.contains(tt))) {
        return t;
      }
    }
  }
  // 4. Cross-field fallback: previously remembered via title but the
  // new file exposes the same label in language, or vice versa.
  // We canonicalize the cross-field side too.
  if (wantLangCanon.isNotEmpty) {
    for (final t in real) {
      final canonFromTitle = _canonicalLanguage(t.title);
      if (canonFromTitle.isNotEmpty && canonFromTitle == wantLangCanon) {
        return t;
      }
    }
  }
  if (wantTitleNorm.isNotEmpty) {
    final wantTitleCanon = _canonicalLanguage(wantTitle);
    if (wantTitleCanon.isNotEmpty) {
      for (final t in real) {
        if (_canonicalLanguage(t.language) == wantTitleCanon) return t;
      }
    }
  }
  return null;
}

/// Same logic for audio tracks — the auto-restore problem is
/// identical there (Audio selection lost on episode change). Pulled
/// into its own function so the call site reads as the intent
/// rather than re-using a "subtitle" name.
TrackCandidate? findBestAudioTrack({
  required List<TrackCandidate> tracks,
  String? wantLanguage,
  String? wantTitle,
}) =>
    findBestSubtitleTrack(
      tracks: tracks,
      wantLanguage: wantLanguage,
      wantTitle: wantTitle,
    );

String _normalize(String? raw) {
  if (raw == null) return '';
  return raw.trim().toLowerCase();
}
