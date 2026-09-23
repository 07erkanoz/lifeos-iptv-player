// Run: flutter test tool/playlist_benchmark_test.dart
// Synthetic host measurements; timer gaps are NOT Flutter rendered frame times.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';
import 'package:lifeostv/data/services/xmltv_parser.dart';

Future<Map<String, dynamic>> measure(
  String kind,
  int rows,
  int bytes,
  String mode,
  FutureOr<int> Function() action,
) async {
  final watch = Stopwatch()..start();
  var last = 0, maxGap = 0, ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
    final now = watch.elapsedMicroseconds;
    final gap = now - last;
    if (gap > maxGap) maxGap = gap;
    last = now;
    ticks++;
  });
  await Future<void>.delayed(const Duration(milliseconds: 30));
  final started = watch.elapsedMicroseconds;
  final actual = await action();
  final elapsed = watch.elapsedMicroseconds - started;
  await Future<void>.delayed(const Duration(milliseconds: 30));
  timer.cancel();
  expect(actual, rows);
  return {
    'kind': kind,
    'rows': rows,
    'bytes': bytes,
    'mode': mode,
    'wallMs': elapsed / 1000,
    'maxMainTimerGapMs': maxGap / 1000,
    'ticks': ticks,
    'processRssMiB': ProcessInfo.currentRss / 1048576,
  };
}

void main() {
  test('playlist parsing responsiveness measurements', () async {
    final samples = <Map<String, dynamic>>[];
    for (final rows in [10000, 50000, 100000]) {
      final body = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < rows; i++) {
        body.writeln(
          '#EXTINF:-1 tvg-id="ch$i" group-title="Group ${i % 50}",Channel $i',
        );
        body.writeln('https://example.invalid/$i.ts');
      }
      final bytes = utf8.encode(body.toString());
      for (var run = 0; run < 3; run++) {
        samples.add(
          await measure(
            'm3u',
            rows,
            bytes.length,
            'main',
            () => parseM3URaw(utf8.decode(bytes)).entries.length,
          ),
        );
        samples.add(
          await measure(
            'm3u',
            rows,
            bytes.length,
            'worker',
            () async => (await parseM3UBytesAsync(bytes)).entries.length,
          ),
        );
      }
    }
    for (final rows in [10000, 50000]) {
      final body = StringBuffer('<tv>');
      for (var i = 0; i < rows; i++) {
        body.write(
          '<programme channel="ch${i % 1000}" start="20260923100000 +0000" stop="20260923110000 +0000"><title>Program $i</title><desc>Synthetic programme description</desc></programme>',
        );
      }
      body.write('</tv>');
      final bytes = utf8.encode(body.toString());
      int count(XmltvParseResult r) =>
          r.programsByChannel.values.fold(0, (n, p) => n + p.length);
      for (var run = 0; run < 3; run++) {
        samples.add(
          await measure(
            'xmltv',
            rows,
            bytes.length,
            'main',
            () => count(parseXmltv(utf8.decode(bytes))),
          ),
        );
        samples.add(
          await measure(
            'xmltv',
            rows,
            bytes.length,
            'worker',
            () async => count(await parseXmltvBytesAsync(bytes)),
          ),
        );
      }
    }
    await File(
      'docs/playlist-fixes-2026-09-23/parser-benchmark.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'runtime': Platform.version,
        'note':
            'Flutter test host; same current parser main vs worker; timer gaps are not frame times; RSS includes test harness and GC history.',
        'samples': samples,
      }),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
