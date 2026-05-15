import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/presentation/widgets/content/expanded_trailer_dialog.dart';

void main() {
  group('computeExpandedTrailerSize — 16:9 letterbox math', () {
    test('wide viewport — height is the limiting axis', () {
      // 1920 × 1080: 0.9× → 1728 × 972.
      // 1728 × 9/16 = 972 (matches the available height exactly).
      final s = computeExpandedTrailerSize(const Size(1920, 1080));
      expect(s.width, closeTo(1728, 0.5));
      expect(s.height, closeTo(972, 0.5));
      expect(s.width / s.height, closeTo(16 / 9, 0.01));
    });

    test('square viewport — width is the limiting axis', () {
      // 1000 × 1000: 0.9× → 900 × 900. Width fits to 900,
      // height becomes 900 × 9/16 = 506.25.
      final s = computeExpandedTrailerSize(const Size(1000, 1000));
      expect(s.width, closeTo(900, 0.5));
      expect(s.height, closeTo(506.25, 0.5));
      expect(s.width / s.height, closeTo(16 / 9, 0.01));
    });

    test('portrait viewport — width is the limiting axis', () {
      // 600 × 1200: 0.9× → 540 × 1080. Width fits to 540,
      // height becomes 540 × 9/16 = 303.75.
      final s = computeExpandedTrailerSize(const Size(600, 1200));
      expect(s.width, closeTo(540, 0.5));
      expect(s.height, closeTo(303.75, 0.5));
      expect(s.width / s.height, closeTo(16 / 9, 0.01));
    });

    test(
      'very wide viewport (ultra-wide monitor) — falls back to '
      'height-limited so the dialog doesn\'t span the whole desk',
      () {
        // 3440 × 1440: 0.9× → 3096 × 1296.
        // Width-first: 3096 → height 1741, which exceeds 1296.
        // So heightFirst: 1296 × 16/9 = 2304.
        final s = computeExpandedTrailerSize(const Size(3440, 1440));
        expect(s.height, closeTo(1296, 0.5));
        expect(s.width, closeTo(2304, 0.5));
        expect(s.width / s.height, closeTo(16 / 9, 0.01));
      },
    );

    test('custom scale parameter is honored', () {
      // 0.5 scale on 1920 × 1080 → max 960 × 540 area.
      final s = computeExpandedTrailerSize(
        const Size(1920, 1080),
        scale: 0.5,
      );
      expect(s.width, closeTo(960, 0.5));
      expect(s.height, closeTo(540, 0.5));
      expect(s.width / s.height, closeTo(16 / 9, 0.01));
    });

    test('result is always 16:9 regardless of input aspect ratio', () {
      // Pick a grab-bag of viewport sizes and check the aspect ratio
      // is always 16:9 within rounding tolerance.
      const cases = [
        Size(2560, 1440), // QHD
        Size(1366, 768), // common laptop
        Size(800, 600), // small old monitor
        Size(414, 896), // mobile portrait
        Size(896, 414), // mobile landscape
      ];
      for (final size in cases) {
        final s = computeExpandedTrailerSize(size);
        expect(
          s.width / s.height,
          closeTo(16 / 9, 0.01),
          reason: 'viewport=$size produced size $s with non-16:9 aspect',
        );
      }
    });
  });
}
