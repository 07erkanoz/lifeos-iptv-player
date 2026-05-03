import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/xmltv_parser.dart';

XmltvParseResult _build(List<String> channelIds) {
  // We only need the keys/normalizedIndex for findXmltvChannelId — the
  // program lists themselves can be empty.
  final programs = <String, List<XmltvProgram>>{
    for (final id in channelIds) id: const [],
  };
  final normalized = <String, String>{};
  for (final id in channelIds) {
    normalized.putIfAbsent(normalizeChannelId(id), () => id);
  }
  return XmltvParseResult(
    programsByChannel: programs,
    normalizedIndex: normalized,
  );
}

void main() {
  group('normalizeChannelId', () {
    test('lowercases the input', () {
      expect(normalizeChannelId('CNN'), 'cnn');
    });

    test('strips ".tr" and ".com.tr" suffixes (Turkish XMLTV feeds)', () {
      expect(normalizeChannelId('trt1.tr'), 'trt1');
      expect(normalizeChannelId('haberturk.com.tr'), 'haberturk');
    });

    test('removes spaces, dots, underscores, hyphens', () {
      expect(normalizeChannelId('TRT 1'), 'trt1');
      expect(normalizeChannelId('show_tv'), 'showtv');
      expect(normalizeChannelId('star-tv'), 'startv');
      expect(normalizeChannelId('TRT.HABER'), 'trthaber');
    });
  });

  group('findXmltvChannelId — 4-phase matcher', () {
    test('phase 1: exact match wins', () {
      final xmltv = _build(['CNN.us', 'BBC.uk']);
      expect(findXmltvChannelId('CNN.us', xmltv), 'CNN.us');
    });

    test('phase 2: case-insensitive match when no exact', () {
      final xmltv = _build(['CNN.us']);
      expect(findXmltvChannelId('cnn.us', xmltv), 'CNN.us');
    });

    test('phase 3: prefix match (XMLTV key starts with searchId + delimiter)', () {
      final xmltv = _build(['cnn.us', 'cnnint.us']);
      // searchId "cnn" prefixes "cnn.us" with a "." delimiter → match
      expect(findXmltvChannelId('cnn', xmltv), 'cnn.us');
    });

    test('phase 4: normalized match strips suffixes / punctuation', () {
      // XMLTV has "TRT 1.tr" → normalizes to "trt1"; we search "TRT1"
      final xmltv = _build(['TRT 1.tr']);
      expect(findXmltvChannelId('TRT1', xmltv), 'TRT 1.tr');
    });

    test('returns null when nothing matches at any phase', () {
      final xmltv = _build(['CNN.us', 'BBC.uk']);
      expect(findXmltvChannelId('SomethingElse', xmltv), isNull);
    });

    test('empty searchId returns null', () {
      final xmltv = _build(['CNN.us']);
      expect(findXmltvChannelId('', xmltv), isNull);
    });
  });
}
