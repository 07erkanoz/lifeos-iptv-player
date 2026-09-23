// flutter test tool/xmltv_events_benchmark_test.dart --reporter expanded
// Baseline parser copied from 91487ac for equal-output performance comparison.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:lifeostv/data/services/xmltv_parser.dart';
import 'playlist_benchmark_test.dart' show measure;

Future<int> runXmltvWorker(String input, bool dom) => Isolate.run(() {
  final result = dom ? _parseDomBaseline(input) : parseXmltv(input);
  return result.programsByChannel.values.fold<int>(0, (n, p) => n + p.length);
});

void main() {
  test('50k XMLTV equal-output worker benchmark', () async {
    final body = StringBuffer('<tv>');
    for (var i = 0; i < 50000; i++) {
      body.write(
        '<programme channel="ch${i % 1000}" start="20260923100000 +0000" stop="20260923110000 +0000"><title>Program $i</title><desc>Fixture description $i</desc></programme>',
      );
    }
    body.write('</tv>');
    final input = body.toString();
    final samples = <Map<String, dynamic>>[];
    for (final dom in [true, false]) {
      samples.add(
        await measure(
          'xmltv',
          50000,
          utf8.encode(input).length,
          dom ? 'dom-worker-baseline' : 'events-worker',
          () => runXmltvWorker(input, dom),
        ),
      );
    }
    final output = {
      'note':
          'Synthetic Linux host, 50000 programmes. Both modes return the same count and metadata model. Timer gaps are not frame times; RSS is the entire test process, not isolated peak memory. Network bytes are still bounded and buffered before parsing.',
      'samples': samples,
    };
    File(
      'docs/sync-media-2026-09-23/xmltv-benchmark.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
    // ignore: avoid_print
    print(jsonEncode(output));
  });
}

DateTime? _parseXmltvDate(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return null;

  try {
    // Remove whitespace-only parts, take the timestamp
    final parts = dateStr.trim().split(RegExp(r'\s+'));
    final ts = parts[0];
    if (!RegExp(r'^\d{14}$').hasMatch(ts)) return null;

    final year = int.parse(ts.substring(0, 4));
    final month = int.parse(ts.substring(4, 6));
    final day = int.parse(ts.substring(6, 8));
    final hour = int.parse(ts.substring(8, 10));
    final minute = int.parse(ts.substring(10, 12));
    final second = int.parse(ts.substring(12, 14));

    final localFields = DateTime.utc(year, month, day, hour, minute, second);
    if (localFields.year != year ||
        localFields.month != month ||
        localFields.day != day ||
        localFields.hour != hour ||
        localFields.minute != minute ||
        localFields.second != second) {
      return null;
    }

    // Parse timezone offset if present (e.g. "+0300")
    if (parts.length > 1) {
      final tzStr = parts[1];
      final tzMatch = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(tzStr);
      if (tzMatch != null) {
        final sign = tzMatch.group(1) == '+' ? 1 : -1;
        final tzHours = int.parse(tzMatch.group(2)!);
        final tzMinutes = int.parse(tzMatch.group(3)!);
        if (tzHours > 23 || tzMinutes > 59) return null;
        final offset = Duration(hours: tzHours, minutes: tzMinutes) * sign;
        // Create UTC time by subtracting the offset, then convert to local
        return DateTime.utc(
          year,
          month,
          day,
          hour,
          minute,
          second,
        ).subtract(offset).toLocal();
      }
    }

    if (parts.length > 1) return null;
    // No timezone — assume UTC
    return DateTime.utc(year, month, day, hour, minute, second).toLocal();
  } catch (_) {
    return null;
  }
}

XmltvParseResult _parseDomBaseline(String xmlContent, {DateTime? now}) {
  final programsByChannel = <String, List<XmltvProgram>>{};

  try {
    final document = XmlDocument.parse(xmlContent);
    final root = document.rootElement;

    // Parse <programme> elements
    for (final programme in root.findAllElements('programme')) {
      final channelId = programme.getAttribute('channel');
      if (channelId == null || channelId.isEmpty) continue;

      final startStr = programme.getAttribute('start');
      final stopStr = programme.getAttribute('stop');

      final start = _parseXmltvDate(startStr);
      final stop = _parseXmltvDate(stopStr);
      if (start == null || stop == null || !stop.isAfter(start)) continue;
      if (now != null &&
          (!stop.isAfter(now.subtract(const Duration(hours: 6))) ||
              !start.isBefore(now.add(const Duration(days: 7))))) {
        continue;
      }

      // Extract title (first <title> element)
      final titleEl = programme.findElements('title').firstOrNull;
      final title = titleEl?.innerText.trim() ?? '';
      if (title.isEmpty) continue;

      // Extract description
      final descEl = programme.findElements('desc').firstOrNull;
      final description = descEl?.innerText.trim();

      // Extract category
      final catEl = programme.findElements('category').firstOrNull;
      final category = catEl?.innerText.trim();

      programsByChannel
          .putIfAbsent(channelId, () => [])
          .add(
            XmltvProgram(
              channelId: channelId,
              title: title,
              description: description,
              category: category,
              start: start,
              stop: stop,
            ),
          );
    }

    // Sort each channel's programs by start time
    for (final programs in programsByChannel.values) {
      programs.sort((a, b) => a.start.compareTo(b.start));
    }
  } catch (_) {
    // XML parse failed — return empty
  }

  // Build normalized index for fast lookups
  final normalizedIndex = <String, String>{};
  for (final channelId in programsByChannel.keys) {
    final normalized = normalizeChannelId(channelId);
    // First match wins (don't overwrite)
    normalizedIndex.putIfAbsent(normalized, () => channelId);
  }

  return XmltvParseResult(
    programsByChannel: programsByChannel,
    normalizedIndex: normalizedIndex,
  );
}
