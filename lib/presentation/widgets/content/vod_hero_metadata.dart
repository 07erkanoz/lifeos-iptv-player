import 'package:drift/drift.dart' show Value;
import 'package:lifeostv/data/datasources/local/database.dart';

/// Adds the selected Xtream title's detail fields without losing catalogue
/// values when a provider sends an incomplete info response.
Channel enrichVodHero(Channel channel, Map<String, dynamic> response) {
  final raw = response['info'];
  if (raw is! Map) return channel;
  String? value(Object? input) {
    final result = input?.toString().trim();
    return result == null || result.isEmpty || result.toLowerCase() == 'null'
        ? null
        : result;
  }

  String? backdrop;
  final path = raw['backdrop_path'];
  if (path is List) {
    for (final image in path) {
      backdrop = value(image);
      if (backdrop != null) break;
    }
  } else {
    backdrop = value(path);
  }
  final poster = value(raw['movie_image']) ?? value(raw['cover']);
  final rating = double.tryParse(value(raw['rating']) ?? '');
  final date =
      value(raw['release_date']) ??
      value(raw['releasedate']) ??
      value(raw['year']);
  final year = date == null
      ? null
      : RegExp(r'\b\d{4}\b').firstMatch(date)?.group(0);

  return channel.copyWith(
    // A portrait cover is never promoted to a wide backdrop. The hero keeps
    // it as its poster and renders the whole image on the right.
    backdropPath: backdrop != null
        ? Value(backdrop)
        : poster != null
        ? const Value(null)
        : const Value.absent(),
    streamIcon: poster == null ? const Value.absent() : Value(poster),
    plot: Value(
      value(raw['plot']) ?? value(raw['description']) ?? channel.plot,
    ),
    genre: Value(value(raw['genre']) ?? channel.genre),
    rating: rating == null || rating <= 0
        ? const Value.absent()
        : Value(rating),
    year: year == null ? const Value.absent() : Value(year),
  );
}
