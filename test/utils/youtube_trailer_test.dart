import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/utils/youtube_trailer.dart';

Channel _ch({
  required String name,
  required String type,
  String? year,
  String? trailer,
}) {
  return Channel(accountId: 0,
    streamId: 1,
    name: name,
    type: type,
    categoryId: 'cat',
    streamIcon: null,
    rating: null,
    year: year,
    added: null,
    backdropPath: null,
    youtubeTrailer: trailer,
    genre: null,
    plot: null,
    director: null,
    cast: null,
    streamUrl: null,
    epgChannelId: null,
  );
}

void main() {
  group('youtubeSearchTrailerUrl', () {
    test('appends "trailer" and URL-encodes the query', () {
      final url = youtubeSearchTrailerUrl('The Matrix');
      expect(url, 'https://www.youtube.com/results?search_query=The+Matrix+trailer');
    });

    test('includes year when present', () {
      final url = youtubeSearchTrailerUrl('Dune', year: '2021');
      expect(url, contains('Dune+2021+trailer'));
    });

    test('omits year segment when null/empty', () {
      expect(youtubeSearchTrailerUrl('Inception', year: null),
          'https://www.youtube.com/results?search_query=Inception+trailer');
      expect(youtubeSearchTrailerUrl('Inception', year: ''),
          'https://www.youtube.com/results?search_query=Inception+trailer');
    });

    test('encodes Turkish characters and spaces', () {
      final url = youtubeSearchTrailerUrl('Çağrı');
      // URI.encodeQueryComponent encodes 'Ç' (%C3%87) and 'ı' (%C4%B1)
      expect(url, contains('%C3%87a%C4%9Fr%C4%B1+trailer'));
    });
  });

  group('trailerUrlForChannel', () {
    test('returns null for live channels (no trailer concept)', () {
      expect(trailerUrlForChannel(_ch(name: 'CNN', type: 'live')), isNull);
    });

    test('uses canonical URL when channel.youtubeTrailer is a full URL', () {
      final ch = _ch(
        name: 'Test',
        type: 'movie',
        trailer: 'https://www.youtube.com/watch?v=abc123',
      );
      expect(trailerUrlForChannel(ch), 'https://www.youtube.com/watch?v=abc123');
    });

    test('expands bare 11-char video id into a watch URL', () {
      final ch = _ch(name: 'Test', type: 'movie', trailer: 'dQw4w9WgXcQ');
      expect(trailerUrlForChannel(ch),
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('falls back to YouTube search when trailer field is empty / sentinel', () {
      for (final sentinel in ['', '   ', 'null', 'N/A', 'none', '0']) {
        final ch = _ch(
          name: 'Foo',
          type: 'movie',
          year: '2024',
          trailer: sentinel,
        );
        final url = trailerUrlForChannel(ch);
        expect(url, contains('search_query=Foo+2024+trailer'),
            reason: 'sentinel "$sentinel" should fall through');
      }
    });

    test('falls back to search when trailer field is null', () {
      final ch = _ch(name: 'Foo', type: 'movie', year: '2024', trailer: null);
      expect(trailerUrlForChannel(ch),
          contains('search_query=Foo+2024+trailer'));
    });

    test('non-11-char non-URL strings (rare malformed values) fall back to search', () {
      // 8-char garbage that isn't a valid video id and isn't an http URL.
      final ch = _ch(name: 'Bar', type: 'series', trailer: 'abcd1234');
      expect(trailerUrlForChannel(ch),
          contains('search_query=Bar+trailer'));
    });
  });
}
