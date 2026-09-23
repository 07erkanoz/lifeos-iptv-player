import 'dart:io';
import 'package:lifeostv/data/services/m3u_parser.dart';

void main() {
  for (final count in [1000, 10000, 50000, 100000]) {
    final b = StringBuffer('#EXTM3U\n');
    for (var i=0; i<count; i++) {
      b.writeln('#EXTINF:-1 tvg-id="ch$i" group-title="Group ${i%50}",Channel $i');
      b.writeln('https://example.invalid/$i.ts');
    }
    final body = b.toString();
    final times = <int>[];
    var collisions = 0;
    for (var run=0; run<3; run++) {
      final sw = Stopwatch()..start();
      final parsed = parseM3URaw(body);
      final result = buildParseResult(parsed.entries);
      final ids = <int>{};
      for (final e in result.entries) {
        ids.add(stableM3uChannelId(url:e.url, name:e.name));
      }
      sw.stop();
      times.add(sw.elapsedMilliseconds);
      collisions = count-ids.length;
    }
    times.sort();
    print('rows=$count bytes=${body.length} medianMs=${times[1]} sampleMs=$times collisions=$collisions processRssMiB=${(ProcessInfo.currentRss/1048576).toStringAsFixed(1)}');
  }
}
