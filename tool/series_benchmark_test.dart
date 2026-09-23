// flutter test tool/series_benchmark_test.dart --reporter expanded
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/m3u_series_catalog.dart';
import 'playlist_benchmark_test.dart' show measure;

void main() {
  test('100k M3U episode grouping responsiveness', () async {
    final channels = List.generate(100000, (i) => Channel(
      accountId: 1, streamId: i + 1, name: 'Show ${i ~/ 100} S01E${i % 100 + 1}',
      type: 'series', categoryId: 'shows', streamUrl: 'https://example.invalid/$i.mp4'));
    final samples = <Map<String, dynamic>>[];
    for (final worker in [false, true]) {
      final result = await measure('m3u-series-grouping', 1000, 0, worker ? 'worker' : 'main', () async {
        final catalog = worker ? await buildM3uSeriesCatalogAsync(channels) : buildM3uSeriesCatalog(channels);
        expect(catalog.byEpisode.length, 100000);
        return catalog.series.length;
      });
      result['episodeCount'] = channels.length;
      samples.add(result);
    }
    final output = {'note': 'Synthetic host test. Timer gaps are not rendered frames; process RSS includes test runner and retained inputs.', 'samples': samples};
    File('docs/navigation-fixes-2026-09-23/series-benchmark.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
    // ignore: avoid_print
    print(jsonEncode(output));
  });
}
