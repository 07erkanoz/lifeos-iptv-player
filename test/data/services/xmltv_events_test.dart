import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/xmltv_parser.dart';

void main() {
  const programme =
      '<programme channel="TRT.tr" start="20260923100000 +0000" stop="20260923110000 +0000">'
      '<title>Türkçe &amp; <b>haber</b><![CDATA[ <canlı>]]></title><title>Ignored alternative</title>'
      '<desc>First <i>description</i></desc><category>News</category></programme>';
  test(
    'event parser preserves entities, nested text, CDATA and first language',
    () {
      final result = parseXmltv(
        '<tv><channel id="ignored"><display-name>Name</display-name></channel>$programme</tv>',
      );
      final p = result.programsByChannel['TRT.tr']!.single;
      expect(p.title, 'Türkçe & haber <canlı>');
      expect(p.description, 'First description');
      expect(p.category, 'News');
      expect(result.normalizedIndex['trt'], 'TRT.tr');
    },
  );
  test('self-closing fields and invalid tail never leak into next programme', () {
    final empty =
        '<programme channel="x" start="20260923100000 +0000" stop="20260923110000 +0000"><title/><desc/></programme>';
    expect(parseXmltv('<tv>$empty$programme</tv>').programsByChannel.keys, [
      'TRT.tr',
    ]);
    expect(
      parseXmltv('<tv>$programme<broken></tv>').programsByChannel,
      isEmpty,
    );
  });
  test(
    'worker preserves UTF-8 and cancellation terminates obsolete work',
    () async {
      final result = await parseXmltvBytesAsync(
        utf8.encode('<tv>$programme</tv>'),
      );
      expect(
        result.programsByChannel['TRT.tr']!.single.title,
        contains('Türkçe'),
      );
      final cancel = Completer<void>();
      final data = utf8.encode(
        '<tv>${List.filled(20000, programme).join()}</tv>',
      );
      final work = parseXmltvBytesAsync(data, cancelled: cancel.future);
      final check = expectLater(work, throwsA(isA<XmltvParseCancelled>()));
      cancel.complete();
      await check;
    },
  );
  test(
    'forced cache refresh and clear invoke transport/worker cancellation',
    () async {
      var cancelled = 0;
      final cache = XmltvCache(
        load: (_) async => parseXmltv('<tv>$programme</tv>'),
        onClear: () {
          cancelled++;
        },
      );
      await cache.fetch('https://example.invalid/feed');
      await cache.fetch('https://example.invalid/feed', force: true);
      expect(cancelled, 1);
      cache.clear();
      expect(cancelled, 2);
    },
  );
  test(
    'event parser filters expired programmes before collecting their text',
    () {
      expect(
        parseXmltv(
          '<tv>$programme</tv>',
          now: DateTime.utc(2027),
        ).programsByChannel,
        isEmpty,
      );
    },
  );
}
