import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';
import 'package:lifeostv/data/services/xmltv_parser.dart';

void main() {
  test(
    'HTTP 200 HTML/JSON errors cannot resolve into relative stream URLs',
    () async {
      for (final body in [
        '<html>\n<title>Login</title>\n</html>',
        '{"error":"expired"}',
      ]) {
        await expectLater(
          parseM3UBytesAsync(
            utf8.encode(body),
            baseUrl: 'https://example.invalid/list',
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'quoted commas/apostrophes, BOM, missing URL and relative resolution',
    () async {
      final result = await parseM3UBytesAsync(
        utf8.encode('''\ufeff#EXTM3U x-tvg-url="../guide.xml"
#EXTINF:-1,Missing
#EXTINF:-1 TVG-ID=one group-title="Films, John's" tvg-name="Fallback",Actual, Name
../film.mp4?token=secret
'''),
        baseUrl: 'https://example.invalid/list/a.m3u',
      );
      expect(result.entries, hasLength(1));
      final e = result.entries.single;
      expect(e.name, 'Actual, Name');
      expect(e.groupTitle, "Films, John's");
      expect(e.tvgId, 'one');
      expect(e.url, 'https://example.invalid/film.mp4?token=secret');
      expect(result.epgUrl, 'https://example.invalid/guide.xml');
      expect(classifyStreamType(url: e.url), 'movie');
    },
  );
  test('name attributes are not interpreted as header attributes', () {
    final e = parseM3U(
      '#EXTINF:-1 tvg-id="a",Title tvg-id="b"\nhttps://example.invalid/live.ts',
    ).single;
    expect(e.tvgId, 'a');
  });
  test(
    'XMLTV rejects invalid calendar dates, reversed times and far future',
    () async {
      String programme(String start, String stop, String title) =>
          '<programme channel="a" start="$start +0000" stop="$stop +0000"><title>$title</title></programme>';
      final xml =
          '<tv>${programme('20260230100000', '20260301120000', 'Bad date')}'
          '${programme('20260923100000', '20260923090000', 'Reversed')}'
          '${programme('20261001100000', '20261001110000', 'Future')}'
          '${programme('20260923100000', '20260923110000', 'Valid')}</tv>';
      final result = await parseXmltvBytesAsync(
        utf8.encode(xml),
        now: DateTime.utc(2026, 9, 23),
      );
      expect(result.programsByChannel['a']!.map((p) => p.title), ['Valid']);
    },
  );
  final result = XmltvParseResult(
    programsByChannel: {'a': []},
    normalizedIndex: {'a': 'a'},
  );
  test('RAM TTL is enforced and feeds are keyed by full URL', () async {
    var now = DateTime.utc(2026), loads = 0;
    final cache = XmltvCache(
      now: () => now,
      load: (_) async {
        loads++;
        return result;
      },
    );
    await cache.fetch('a');
    await cache.fetch('a');
    expect(loads, 1);
    now = now.add(const Duration(hours: 6));
    await cache.fetch('a');
    expect(loads, 2);
    await cache.fetch('b');
    expect(loads, 3);
    await cache.fetch('b', force: true);
    expect(loads, 4);
  });
  test(
    'concurrent loads coalesce; clear blocks a stale cache refill',
    () async {
      final pending = Completer<XmltvParseResult?>();
      var loads = 0;
      final cache = XmltvCache(
        load: (_) {
          loads++;
          return pending.future;
        },
      );
      final a = cache.fetch('a'), b = cache.fetch('a');
      expect(loads, 1);
      cache.clear();
      pending.complete(result);
      await Future.wait([a, b]);
      await cache.fetch('a');
      expect(loads, 2);
    },
  );
}
