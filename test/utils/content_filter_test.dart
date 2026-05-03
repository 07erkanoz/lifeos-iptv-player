import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/utils/content_filter.dart';

void main() {
  group('isAdultContent', () {
    test('flags English keywords (case-insensitive)', () {
      expect(isAdultContent('Adult Movies'), isTrue);
      expect(isAdultContent('XXX HD'), isTrue);
      expect(isAdultContent('Premium +18'), isTrue);
      expect(isAdultContent('TR | EROTIC'), isTrue);
    });

    test('flags Turkish keywords (yetiskin / yetişkin / erotik)', () {
      expect(isAdultContent('Yetişkin Kanalı'), isTrue);
      expect(isAdultContent('YETISKIN HD'), isTrue);
      expect(isAdultContent('Erotik Filmler'), isTrue);
    });

    test('flags Arabic keywords used in MENA IPTV bouquets', () {
      // Two of the keywords in adultKeywords are Arabic strings.
      expect(isAdultContent('قناة للكبار'), isTrue);
    });

    test('does NOT flag innocent content with similar substrings', () {
      // "ADX" contains no adult keyword
      expect(isAdultContent('ADX Sports'), isFalse);
      expect(isAdultContent('Discovery Channel'), isFalse);
      expect(isAdultContent('Yemek 365'), isFalse);
    });

    test('empty string is not adult', () {
      expect(isAdultContent(''), isFalse);
    });
  });

  group('filterAdultContent', () {
    test('removes adult items from a typed list', () {
      final input = [
        ('Discovery', 'safe'),
        ('Adult HD', 'unsafe'),
        ('CNN', 'safe'),
        ('XXX Plus', 'unsafe'),
      ];
      final out = filterAdultContent(input, (item) => item.$1);
      expect(out.map((e) => e.$2).toList(), ['safe', 'safe']);
    });

    test('returns original ordering for non-adult items', () {
      final input = ['BBC', 'CNN', 'Al Jazeera'];
      expect(filterAdultContent(input, (s) => s), input);
    });

    test('empty input → empty output', () {
      expect(filterAdultContent(<String>[], (s) => s), isEmpty);
    });
  });
}
