import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/m3u_parser.dart';

void main() {
  group('stableM3uChannelId', () {
    test('is deterministic — same input → same id', () {
      final a = stableM3uChannelId(url: 'http://x/y.m3u8', name: 'CNN');
      final b = stableM3uChannelId(url: 'http://x/y.m3u8', name: 'CNN');
      expect(a, b);
    });

    test('different url OR different name → different id (collisions are rare)', () {
      final id1 = stableM3uChannelId(url: 'http://a/1.m3u8', name: 'CNN');
      final id2 = stableM3uChannelId(url: 'http://b/1.m3u8', name: 'CNN');
      final id3 = stableM3uChannelId(url: 'http://a/1.m3u8', name: 'BBC');
      expect(id1, isNot(id2));
      expect(id1, isNot(id3));
    });

    test('always returns a positive 31-bit int (fits any signed-int column)', () {
      final values = [
        stableM3uChannelId(url: 'http://x', name: 'a'),
        stableM3uChannelId(url: 'http://example.com/very/long/path/foo.m3u8', name: 'X'),
        stableM3uChannelId(url: 'http://x', name: null),
      ];
      for (final v in values) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });

    test('null and empty name are treated identically (URL-only)', () {
      final nullName = stableM3uChannelId(url: 'http://x', name: null);
      final emptyName = stableM3uChannelId(url: 'http://x', name: '');
      expect(nullName, emptyName);
    });
  });

  group('classifyStreamType', () {
    test('tvg-type "live" wins over everything', () {
      expect(
        classifyStreamType(
          url: 'http://x/movie/foo.mp4',  // looks like a movie
          tvgType: 'live',                // …but tvg-type says live
        ),
        'live',
      );
    });

    test('Xtream-style /movie/ path → movie', () {
      expect(classifyStreamType(url: 'http://x:8080/movie/u/p/1.mp4'), 'movie');
    });

    test('Xtream-style /series/ path → series', () {
      expect(classifyStreamType(url: 'http://x:8080/series/u/p/1.mp4'), 'series');
    });

    test('Xtream-style /live/ path → live', () {
      expect(classifyStreamType(url: 'http://x:8080/live/u/p/1.ts'), 'live');
    });

    test('S01E02 episode marker in name boosts series score', () {
      expect(
        classifyStreamType(
          url: 'http://x/foo.mp4',
          name: 'My Show S01E02',
        ),
        'series',
      );
    });

    test('plain http URL with no signals defaults to live', () {
      expect(classifyStreamType(url: 'http://x/stream'), 'live');
    });
  });

  group('parseM3URaw', () {
    test('extracts url-tvg from #EXTM3U header', () {
      final result = parseM3URaw('''
#EXTM3U url-tvg="http://example.com/epg.xml"
#EXTINF:-1,Test
http://x/1.ts
''');
      expect(result.epgUrl, 'http://example.com/epg.xml');
      expect(result.entries, hasLength(1));
      expect(result.entries.first.name, 'Test');
      expect(result.entries.first.url, 'http://x/1.ts');
    });

    test('parses tvg-id, tvg-name, tvg-logo, group-title attributes', () {
      final result = parseM3URaw('''
#EXTM3U
#EXTINF:-1 tvg-id="cnn.us" tvg-name="CNN" tvg-logo="http://l/cnn.png" group-title="News",CNN
http://x/cnn.m3u8
''');
      expect(result.entries, hasLength(1));
      final e = result.entries.first;
      expect(e.tvgId, 'cnn.us');
      expect(e.tvgName, 'CNN');
      expect(e.tvgLogo, 'http://l/cnn.png');
      expect(e.groupTitle, 'News');
    });

    test('group-title is sticky across entries that omit it', () {
      final result = parseM3URaw('''
#EXTM3U
#EXTINF:-1 group-title="Sports",ESPN
http://x/1
#EXTINF:-1,Eurosport
http://x/2
''');
      expect(result.entries, hasLength(2));
      // Second entry inherits "Sports" because it didn't declare its own.
      expect(result.entries[1].groupTitle, 'Sports');
    });

    test('skips dummy URLs (http://blank, /null, etc.)', () {
      final result = parseM3URaw('''
#EXTM3U
#EXTINF:-1,Real
http://x/real.ts
#EXTINF:-1,Fake
http://blank
#EXTINF:-1,AlsoFake
http://x/null
''');
      // First is real; "http://blank" is filtered, "/null" is filtered too
      // (length-gated dummy heuristic).
      expect(result.entries.map((e) => e.name), contains('Real'));
      expect(result.entries.map((e) => e.name), isNot(contains('Fake')));
    });

    test('handles CRLF line endings', () {
      final result = parseM3URaw('#EXTM3U\r\n#EXTINF:-1,X\r\nhttp://x/1\r\n');
      expect(result.entries, hasLength(1));
      expect(result.entries.first.name, 'X');
    });

    test('empty input yields empty result, no crash', () {
      final result = parseM3URaw('');
      expect(result.entries, isEmpty);
      expect(result.epgUrl, isNull);
    });
  });
}
