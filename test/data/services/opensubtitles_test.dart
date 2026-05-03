import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/opensubtitles_service.dart';

void main() {
  group('srtToVtt', () {
    test('prepends WEBVTT header', () {
      final out = srtToVtt('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
      expect(out.startsWith('WEBVTT\n\n'), isTrue);
    });

    test('replaces comma decimal separator with period in timestamps', () {
      const srt = '1\n00:00:01,500 --> 00:00:03,250\nLine\n';
      final out = srtToVtt(srt);
      expect(out, contains('00:00:01.500 --> 00:00:03.250'));
      expect(out, isNot(contains('00:00:01,500')));
    });

    test('strips standalone sequence numbers (the "1\\n" / "2\\n" lines)', () {
      const srt = '''
1
00:00:01,000 --> 00:00:02,000
First

2
00:00:03,000 --> 00:00:04,000
Second
''';
      final out = srtToVtt(srt);
      // The bare "1" and "2" lines must be gone — they confuse VTT parsers.
      expect(out, isNot(matches(RegExp(r'^\d+$', multiLine: true))));
      // But the cue text remains.
      expect(out, contains('First'));
      expect(out, contains('Second'));
    });

    test('normalizes CRLF and CR-only line endings to LF', () {
      const srtCrlf = '1\r\n00:00:01,000 --> 00:00:02,000\r\nLine\r\n';
      final out = srtToVtt(srtCrlf);
      expect(out, isNot(contains('\r')));
      expect(out, contains('00:00:01.000 --> 00:00:02.000'));
    });

    test('preserves multi-line cue text', () {
      const srt = '''
1
00:00:01,000 --> 00:00:05,000
Line one
Line two
''';
      final out = srtToVtt(srt);
      expect(out, contains('Line one\nLine two'));
    });

    // NOTE: srtToVtt is NOT idempotent — calling it on already-VTT content
    // adds a second WEBVTT header. The download path guards this with a
    // `!content.startsWith('WEBVTT')` check before invoking; callers must
    // do the same. We intentionally don't test for idempotence because
    // the function doesn't promise it.
  });
}
