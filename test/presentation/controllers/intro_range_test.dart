import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/intro_range.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

void main() {
  test(
    'skip appears only inside a bounded interval within this media duration',
    () {
      const range = IntroRange(10000, 40000), duration = Duration(minutes: 20);
      expect(range.visibleAt(const Duration(seconds: 9), duration), false);
      expect(range.visibleAt(const Duration(seconds: 10), duration), true);
      expect(range.visibleAt(const Duration(seconds: 40), duration), false);
      expect(
        range.visibleAt(
          const Duration(seconds: 20),
          const Duration(seconds: 30),
        ),
        false,
      );
      expect(range.visibleAt(Duration.zero, Duration.zero), false);
    },
  );
  test('legacy and low-confidence guesses never become skip instructions', () {
    final marker = IntroMarker(
      seriesId: 1,
      accountId: 1,
      season: 1,
      episodeId: 11,
      introStartMs: 1000,
      introEndMs: 10000,
      source: 'legacy',
      confidence: 0,
      isDeleted: false,
      updatedAt: DateTime(2026),
    );
    expect(IntroRange.fromMarker(marker), isNull);
    expect(
      IntroRange.fromMarker(marker.copyWith(source: 'manual', confidence: 1)),
      isNotNull,
    );
    expect(
      IntroRange.fromMarker(
        marker.copyWith(source: 'manual', confidence: 1, isDeleted: true),
      ),
      isNull,
    );
  });
  test(
    'explicit chapter boundaries are used; ordinary chapters are not inferred',
    () {
      const duration = Duration(minutes: 40);
      expect(
        IntroRange.fromChapters([
          {'title': 'Opening', 'time': 25},
          {'title': 'Episode', 'time': 80},
        ], duration)?.endMs,
        80000,
      );
      for (final title in [
        'AÇILIŞ JENERİĞİ',
        'Vorspann',
        'Générique',
        'مقدمة',
      ]) {
        expect(
          IntroRange.fromChapters([
            {'title': title, 'time': 25},
            {'title': 'Episode', 'time': 80},
          ], duration)?.startMs,
          25000,
        );
      }
      expect(
        IntroRange.fromChapters([
          {'title': 'Chapter 1', 'time': 0},
          {'title': 'Chapter 2', 'time': 90},
        ], duration),
        isNull,
      );
      expect(
        IntroRange.fromChapters([
          {'title': 'Intro', 'time': 90},
          {'title': 'Episode', 'time': 80},
        ], duration),
        isNull,
      );
    },
  );
}
