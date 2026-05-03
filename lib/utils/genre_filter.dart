import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/data/datasources/local/database.dart';

/// Channel.genre is a comma- (or `/`, `|`) separated list — TMDB-style.
/// Splits a single channel's genre string into a clean Set of trimmed,
/// non-empty tokens (e.g. "Action, Drama / Thriller" → {Action, Drama, Thriller}).
Set<String> _genreTokens(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  return raw
      .split(RegExp(r'[,/|]'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet();
}

/// Build the union of every genre that appears in [channels], sorted
/// alphabetically. Used to populate the dropdown — capped at 50 entries
/// because some IPTV providers spam dozens of pseudo-genres.
List<String> extractGenres(List<Channel> channels, {int limit = 50}) {
  final all = <String>{};
  for (final ch in channels) {
    all.addAll(_genreTokens(ch.genre));
  }
  final sorted = all.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return sorted.take(limit).toList();
}

/// Keep only channels whose genre string contains [genre] as one of its
/// tokens. Case-insensitive comparison.
///
/// `genre == null` (or empty) is the "All" state — pass-through, fresh list.
List<Channel> filterByGenre(List<Channel> channels, String? genre) {
  if (genre == null || genre.isEmpty) {
    return List<Channel>.from(channels);
  }
  final wanted = genre.toLowerCase();
  return channels.where((ch) {
    final tokens = _genreTokens(ch.genre).map((g) => g.toLowerCase());
    return tokens.contains(wanted);
  }).toList();
}

/// Per-screen "currently selected genre" state. `null` means "All".
/// Two separate notifiers so picking a genre on movies doesn't reset
/// the series filter (and vice versa).
class _GenreFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties
  void set(String? genre) => state = genre;
}

final movieGenreFilterProvider =
    NotifierProvider<_GenreFilterNotifier, String?>(_GenreFilterNotifier.new);

final seriesGenreFilterProvider =
    NotifierProvider<_GenreFilterNotifier, String?>(_GenreFilterNotifier.new);
