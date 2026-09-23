import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

void main() {
  const base = 'http://example.com:8080';
  const u = 'jane';
  const p = 'secret';

  group('StreamUrlBuilder.live', () {
    test('default (auto quality) uses .m3u8 / HLS for adaptive bitrate', () {
      expect(StreamUrlBuilder.live(base, u, p, 42), '$base/live/$u/$p/42.m3u8');
    });

    test('non-auto quality uses .ts (fixed-bitrate MPEG-TS)', () {
      for (final q in [
        StreamQuality.high,
        StreamQuality.medium,
        StreamQuality.low,
      ]) {
        expect(
          StreamUrlBuilder.live(base, u, p, 42, quality: q),
          '$base/live/$u/$p/42.ts',
          reason: 'quality $q should produce .ts URL',
        );
      }
    });
  });

  group('StreamUrlBuilder.movie / .series', () {
    test('movie uses .mkv extension', () {
      expect(StreamUrlBuilder.movie(base, u, p, 7), '$base/movie/$u/$p/7.mkv');
    });

    test('series uses .mkv extension', () {
      expect(
        StreamUrlBuilder.series(base, u, p, 7),
        '$base/series/$u/$p/7.mkv',
      );
    });
  });

  group('provider metadata and escaped path segments', () {
    test('provider container overrides legacy MKV fallback', () {
      expect(
        StreamUrlBuilder.movie(base, u, p, 7, extension: '.MP4'),
        '$base/movie/$u/$p/7.mp4',
      );
      expect(
        StreamUrlBuilder.series(base, u, p, 8, extension: 'webm'),
        '$base/series/$u/$p/8.webm',
      );
    });

    test('direct source is preserved including signed query parameters', () {
      const direct = 'https://cdn.invalid/asset?sig=a%2Fb&expires=123';
      expect(
        StreamUrlBuilder.movie(
          base,
          u,
          p,
          7,
          extension: 'mp4',
          directUrl: direct,
        ),
        direct,
      );
      expect(StreamUrlBuilder.series(base, u, p, 7, directUrl: direct), direct);
    });

    test('credentials stay in single segments with no query or fragment', () {
      const user = 'u/ser ü';
      const password = 'p#q?/%&@';
      for (final url in [
        StreamUrlBuilder.live(base, user, password, 42),
        StreamUrlBuilder.movie(base, user, password, 42),
        StreamUrlBuilder.series(base, user, password, 42),
        StreamUrlBuilder.timeshift(
          base,
          user,
          password,
          42,
          start: DateTime(2026, 9, 23, 12, 30),
          duration: const Duration(minutes: 20),
        ),
      ]) {
        final uri = Uri.parse(url);
        expect(uri.pathSegments[1], user);
        expect(uri.pathSegments[2], password);
        expect(uri.query, isEmpty);
        expect(uri.fragment, isEmpty);
      }
    });

    test('panel prefix and port are retained without double slashes', () {
      final url = StreamUrlBuilder.movie(
        '$base/panel/',
        u,
        p,
        7,
        extension: 'mp4',
      );
      expect(url, '$base/panel/movie/$u/$p/7.mp4');
    });

    test('container cannot inject a second path or query', () {
      expect(
        StreamUrlBuilder.movie(base, u, p, 7, extension: '../other?x'),
        '$base/movie/$u/$p/7.mkv',
      );
    });

    test('missing playback metadata remains distinguishable from MKV', () {
      expect(
        StreamUrlBuilder.vodFromMetadata(base, u, p, 7, {'name': 'Film'}),
        isNull,
      );
    });
  });

  group('StreamUrlBuilder.build', () {
    test('directUrl wins when provided (M3U accounts)', () {
      expect(
        StreamUrlBuilder.build(
          base,
          u,
          p,
          99,
          'live',
          directUrl: 'http://m3u.example/stream.m3u8',
        ),
        'http://m3u.example/stream.m3u8',
      );
    });

    test('empty directUrl is ignored — falls through to type builders', () {
      expect(
        StreamUrlBuilder.build(base, u, p, 99, 'live', directUrl: ''),
        '$base/live/$u/$p/99.m3u8',
      );
    });

    test('dispatches to live/movie/series by type', () {
      expect(
        StreamUrlBuilder.build(base, u, p, 1, 'live'),
        '$base/live/$u/$p/1.m3u8',
      );
      expect(
        StreamUrlBuilder.build(base, u, p, 1, 'movie'),
        '$base/movie/$u/$p/1.mkv',
      );
      expect(
        StreamUrlBuilder.build(base, u, p, 1, 'series'),
        '$base/series/$u/$p/1.mkv',
      );
    });

    test('unknown type falls back to a generic <base>/<u>/<p>/<id> shape', () {
      expect(StreamUrlBuilder.build(base, u, p, 1, 'unknown'), '$base/$u/$p/1');
    });

    test('passes quality through to the live path', () {
      expect(
        StreamUrlBuilder.build(
          base,
          u,
          p,
          1,
          'live',
          quality: StreamQuality.low,
        ),
        '$base/live/$u/$p/1.ts',
      );
    });
  });
}
