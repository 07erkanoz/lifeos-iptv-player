import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/utils/genre_filter.dart';

Channel _ch({required int id, required String name, String? genre}) {
  return Channel(accountId: 0,
    streamId: id,
    name: name,
    type: 'movie',
    categoryId: 'cat',
    streamIcon: null,
    rating: null,
    year: null,
    added: null,
    backdropPath: null,
    youtubeTrailer: null,
    genre: genre,
    plot: null,
    director: null,
    cast: null,
    streamUrl: null,
    epgChannelId: null,
  );
}

void main() {
  final movies = [
    _ch(id: 1, name: 'Mad Max', genre: 'Action, Sci-Fi'),
    _ch(id: 2, name: 'Drive', genre: 'Crime / Drama'),
    _ch(id: 3, name: 'Inception', genre: 'Sci-Fi | Thriller'),
    _ch(id: 4, name: 'NoGenre', genre: null),
    _ch(id: 5, name: 'EmptyGenre', genre: ''),
    _ch(id: 6, name: 'OnlyAction', genre: 'Action'),
  ];

  group('extractGenres', () {
    test('returns the union of all genres, alphabetically', () {
      expect(extractGenres(movies),
          ['Action', 'Crime', 'Drama', 'Sci-Fi', 'Thriller']);
    });

    test('handles comma, slash AND pipe separators uniformly', () {
      final input = [
        _ch(id: 1, name: 'A', genre: 'Action,Drama'),
        _ch(id: 2, name: 'B', genre: 'Action / Comedy'),
        _ch(id: 3, name: 'C', genre: 'Drama|Crime'),
      ];
      expect(extractGenres(input), ['Action', 'Comedy', 'Crime', 'Drama']);
    });

    test('skips null / empty / whitespace-only genre strings', () {
      final input = [
        _ch(id: 1, name: 'A', genre: null),
        _ch(id: 2, name: 'B', genre: ''),
        _ch(id: 3, name: 'C', genre: '   '),
        _ch(id: 4, name: 'D', genre: 'Action'),
      ];
      expect(extractGenres(input), ['Action']);
    });

    test('limit caps the result count', () {
      final many = List<Channel>.generate(
        100,
        (i) => _ch(id: i, name: 'M$i', genre: 'G$i'),
      );
      expect(extractGenres(many, limit: 10), hasLength(10));
    });

    test('empty input → empty result', () {
      expect(extractGenres(<Channel>[]), isEmpty);
    });
  });

  group('filterByGenre', () {
    test('null genre is the All-pass-through, returns a fresh list', () {
      final out = filterByGenre(movies, null);
      expect(out, hasLength(movies.length));
      expect(identical(out, movies), isFalse);
    });

    test('empty string is also pass-through', () {
      final out = filterByGenre(movies, '');
      expect(out, hasLength(movies.length));
    });

    test('matches the requested genre token (comma-separated)', () {
      final out = filterByGenre(movies, 'Action');
      expect(out.map((c) => c.streamId).toList(), [1, 6]);
    });

    test('matches across slash separator', () {
      final out = filterByGenre(movies, 'Crime');
      expect(out.map((c) => c.streamId).toList(), [2]);
    });

    test('matches across pipe separator', () {
      final out = filterByGenre(movies, 'Thriller');
      expect(out.map((c) => c.streamId).toList(), [3]);
    });

    test('case-insensitive match', () {
      expect(
        filterByGenre(movies, 'action').map((c) => c.streamId).toList(),
        [1, 6],
      );
      expect(
        filterByGenre(movies, 'SCI-FI').map((c) => c.streamId).toList(),
        [1, 3],
      );
    });

    test('substring is NOT enough — must be a full token', () {
      // "Act" should not match "Action"
      expect(filterByGenre(movies, 'Act'), isEmpty);
    });

    test('null / empty channel.genre never matches a real query', () {
      final out = filterByGenre(movies, 'Action');
      // Channels 4 (null) and 5 (empty) must be excluded.
      expect(out.any((c) => c.streamId == 4), isFalse);
      expect(out.any((c) => c.streamId == 5), isFalse);
    });
  });
}
