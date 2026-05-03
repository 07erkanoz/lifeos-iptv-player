import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/dlna_service.dart';

void main() {
  group('extractSsdpLocationHeader', () {
    test('parses LOCATION value out of an M-SEARCH response', () {
      const body = 'HTTP/1.1 200 OK\r\n'
          'CACHE-CONTROL: max-age=1800\r\n'
          'DATE: Mon, 03 May 2026 14:00:00 GMT\r\n'
          'EXT:\r\n'
          'LOCATION: http://192.168.1.42:1700/description.xml\r\n'
          'SERVER: webOS/4.0 UPnP/1.0\r\n\r\n';
      expect(extractSsdpLocationHeader(body),
          Uri.parse('http://192.168.1.42:1700/description.xml'));
    });

    test('header lookup is case-insensitive', () {
      const body = 'HTTP/1.1 200 OK\r\nlocation: http://x/d.xml\r\n\r\n';
      expect(extractSsdpLocationHeader(body), Uri.parse('http://x/d.xml'));
    });

    test('returns null when no LOCATION header is present', () {
      const body = 'HTTP/1.1 200 OK\r\nServer: webOS\r\n\r\n';
      expect(extractSsdpLocationHeader(body), isNull);
    });
  });

  group('dlnaMimeForUrl', () {
    test('matches by file extension', () {
      expect(dlnaMimeForUrl('http://x/foo.mp4'), 'video/mp4');
      expect(dlnaMimeForUrl('http://x/foo.mkv'), 'video/x-matroska');
      expect(dlnaMimeForUrl('http://x/foo.ts'), 'video/mp2t');
      expect(dlnaMimeForUrl('http://x/foo.avi'), 'video/x-msvideo');
      expect(dlnaMimeForUrl('http://x/foo.m3u8'),
          'application/vnd.apple.mpegurl');
      expect(dlnaMimeForUrl('http://x/foo.mpd'), 'application/dash+xml');
    });

    test('Xtream /live/ path → MPEG-TS', () {
      expect(
        dlnaMimeForUrl('http://srv:8080/live/u/p/123.unknown'),
        'video/mp2t',
      );
    });

    test('Xtream /movie/ + /series/ → MP4', () {
      expect(dlnaMimeForUrl('http://srv:8080/movie/u/p/1.foo'), 'video/mp4');
      expect(dlnaMimeForUrl('http://srv:8080/series/u/p/1.foo'), 'video/mp4');
    });

    test('extension wins over Xtream path heuristic', () {
      // /live/ + .mkv → mkv beats the heuristic (extension is more reliable)
      expect(dlnaMimeForUrl('http://x/live/foo.mkv'), 'video/x-matroska');
    });

    test('falls back to mp4 when nothing matches', () {
      expect(dlnaMimeForUrl('http://x/stream'), 'video/mp4');
    });

    test('case-insensitive on extension', () {
      expect(dlnaMimeForUrl('http://x/FOO.M3U8'),
          'application/vnd.apple.mpegurl');
    });
  });

  group('xmlEscape', () {
    test('escapes the five XML special characters', () {
      expect(xmlEscape('Tom & Jerry <s01e02> "best" \'episode\''),
          'Tom &amp; Jerry &lt;s01e02&gt; &quot;best&quot; &apos;episode&apos;');
    });

    test('leaves unicode / non-ASCII alone', () {
      expect(xmlEscape('Çağrı – Türkçe'), 'Çağrı – Türkçe');
    });

    test('empty string round-trips', () {
      expect(xmlEscape(''), '');
    });
  });

  group('buildDidlMetadata', () {
    test('embeds title, url and protocolInfo MIME', () {
      final didl = buildDidlMetadata(
        url: 'http://x/foo.mp4',
        title: 'My Movie',
        mime: 'video/mp4',
      );
      expect(didl, contains('<dc:title>My Movie</dc:title>'));
      expect(didl, contains('http-get:*:video/mp4:*'));
      expect(didl, contains('http://x/foo.mp4'));
      expect(didl, startsWith('<?xml'));
      expect(didl, contains('object.item.videoItem'));
    });

    test('escapes XML-unsafe characters in title and url', () {
      final didl = buildDidlMetadata(
        url: 'http://x/foo.mp4?a=1&b=2',
        title: 'Tom & Jerry <2024>',
        mime: 'video/mp4',
      );
      expect(didl, contains('Tom &amp; Jerry &lt;2024&gt;'));
      expect(didl, contains('foo.mp4?a=1&amp;b=2'));
      // Raw "&" or "<" must NOT survive — would break TV's XML parser.
      expect(didl, isNot(contains('& Jerry')));
      expect(didl, isNot(contains('<2024>')));
    });
  });

  group('DlnaDevice.displayName', () {
    test('uses friendly name only when model matches or is missing', () {
      final d = DlnaDevice(
        name: 'Living Room TV',
        controlUrl: Uri.parse('http://x/c'),
        serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      );
      expect(d.displayName, 'Living Room TV');
    });

    test('appends model when it differs from friendly name', () {
      final d = DlnaDevice(
        name: 'Living Room TV',
        modelName: 'OLED55C1',
        controlUrl: Uri.parse('http://x/c'),
        serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      );
      expect(d.displayName, 'Living Room TV (OLED55C1)');
    });

    test('two devices with the same controlUrl are equal', () {
      final a = DlnaDevice(
        name: 'A',
        controlUrl: Uri.parse('http://x/c'),
        serviceType: 'svc',
      );
      final b = DlnaDevice(
        name: 'B (rename)',
        controlUrl: Uri.parse('http://x/c'),
        serviceType: 'svc',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
