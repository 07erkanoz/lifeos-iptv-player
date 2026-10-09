import 'package:lifeostv/data/datasources/local/database.dart';

class IntroRange {
  const IntroRange(this.startMs, this.endMs);
  final int startMs, endMs;
  bool validFor(Duration duration) =>
      startMs >= 0 &&
      endMs > startMs &&
      duration.inMilliseconds > 0 &&
      endMs <= duration.inMilliseconds;
  bool visibleAt(Duration position, Duration duration) =>
      validFor(duration) &&
      position.inMilliseconds >= startMs &&
      position.inMilliseconds < endMs;
  static IntroRange? fromMarker(IntroMarker? marker) =>
      marker == null ||
          marker.isDeleted ||
          marker.confidence < 0.95 ||
          marker.source == 'legacy'
      ? null
      : IntroRange(marker.introStartMs, marker.introEndMs);

  /// Explicit media chapters are evidence; titles/durations alone are not.
  static IntroRange? fromChapters(List chapters, Duration duration) {
    for (var i = 0; i + 1 < chapters.length; i++) {
      final current = chapters[i], next = chapters[i + 1];
      if (current is! Map || next is! Map) continue;
      final title = _normalizeTitle('${current['title'] ?? ''}');
      if (!{
        'intro',
        'opening',
        'opening credits',
        'opening titles',
        'title sequence',
        'açılış',
        'açılış jeneriği',
        'giriş jeneriği',
        'jenerik',
        'vorspann',
        'générique',
        "générique d’ouverture",
        "générique d'ouverture",
        'introducción',
        'cabecera',
        'заставка',
        'вступление',
        'مقدمة',
        'المقدمة',
        'destpêk',
      }.any((candidate) => _normalizeTitle(candidate) == title))
        continue;
      final start = current['time'], end = next['time'];
      if (start is! num || end is! num || !start.isFinite || !end.isFinite)
        continue;
      final range = IntroRange((start * 1000).round(), (end * 1000).round());
      if (range.validFor(duration)) return range;
    }
    return null;
  }

  static String _normalizeTitle(String title) =>
      title.trim().toLowerCase().replaceAll('\u0307', '').replaceAll('ı', 'i');
}
