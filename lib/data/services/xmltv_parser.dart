/// XMLTV Parser Service
/// Tauri epg.service.ts'den port edilmiştir.
///
/// Desteklenen özellikler:
/// - XMLTV XML parse (programme/channel elementleri)
/// - Kanal ID normalizasyonu (lowercase, noktalama kaldır, .tr/.com.tr suffix strip)
/// - 4 aşamalı eşleştirme: exact → case-insensitive → prefix → normalized
/// - 6 saat TTL ile cache
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'bounded_get_client.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml_events.dart';
import 'sync_budget.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════
//  Veri Modelleri
// ═══════════════════════════════════════════════════════════════════

class XmltvProgram {
  final String channelId;
  final String title;
  final String? description;
  final String? category;
  final DateTime start;
  final DateTime stop;

  const XmltvProgram({
    required this.channelId,
    required this.title,
    this.description,
    this.category,
    required this.start,
    required this.stop,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  Kanal ID Normalizasyonu
// ═══════════════════════════════════════════════════════════════════

/// Normalize a channel ID for fuzzy matching.
/// Rules: lowercase → strip .tr/.com.tr suffix → remove spaces/dots/underscores/hyphens
String normalizeChannelId(String id) {
  var normalized = id.toLowerCase();
  // Strip .tr or .com.tr suffix
  normalized = normalized.replaceAll(RegExp(r'\.(com\.)?tr$'), '');
  // Remove spaces, dots, underscores, hyphens
  normalized = normalized.replaceAll(RegExp(r'[\s._-]+'), '');
  return normalized;
}

// ═══════════════════════════════════════════════════════════════════
//  XMLTV Tarih Parse
// ═══════════════════════════════════════════════════════════════════

/// Parse XMLTV date format: "20240115200000 +0300"
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

// ═══════════════════════════════════════════════════════════════════
//  XMLTV XML Parser
// ═══════════════════════════════════════════════════════════════════

class XmltvParseResult {
  /// channel XMLTV ID → list of programs
  final Map<String, List<XmltvProgram>> programsByChannel;

  /// normalized ID → original XMLTV channel ID (for fast lookup)
  final Map<String, String> normalizedIndex;

  const XmltvParseResult({
    required this.programsByChannel,
    required this.normalizedIndex,
  });
}

/// Parse XMLTV XML content into structured program data
XmltvParseResult parseXmltv(String xmlContent, {DateTime? now}) {
  final programsByChannel = <String, List<XmltvProgram>>{};

  // Event parsing keeps only one programme's fields, not a DOM for the feed.
  var depth = 0;
  int? programDepth, fieldDepth;
  String? channelId, field;
  DateTime? start, stop;
  var valid = false;
  final fields = <String, String>{};
  StringBuffer? text;
  void finishElement() {
    if (fieldDepth == depth) {
      fields[field!] = text!.toString().trim();
      field = null;
      fieldDepth = null;
      text = null;
    }
    if (programDepth == depth) {
      final title = fields['title'] ?? '';
      if (valid && title.isNotEmpty) {
        programsByChannel
            .putIfAbsent(channelId!, () => [])
            .add(
              XmltvProgram(
                channelId: channelId,
                title: title,
                description: fields['desc'],
                category: fields['category'],
                start: start!,
                stop: stop!,
              ),
            );
      }
      programDepth = null;
      valid = false;
      fields.clear();
    }
    depth--;
  }

  try {
    for (final event in parseEvents(
      xmlContent,
      validateNesting: true,
      validateDocument: true,
    )) {
      if (event is XmlStartElementEvent) {
        depth++;
        if (event.name == 'programme' && programDepth == null) {
          programDepth = depth;
          final attributes = {
            for (final a in event.attributes) a.name: a.value,
          };
          channelId = attributes['channel'];
          start = _parseXmltvDate(attributes['start']);
          stop = _parseXmltvDate(attributes['stop']);
          valid =
              channelId != null &&
              channelId.isNotEmpty &&
              start != null &&
              stop != null &&
              stop.isAfter(start);
          if (valid && now != null) {
            valid =
                stop!.isAfter(now.subtract(const Duration(hours: 6))) &&
                start!.isBefore(now.add(const Duration(days: 7)));
          }
        } else if (valid &&
            depth == programDepth! + 1 &&
            const {'title', 'desc', 'category'}.contains(event.name) &&
            !fields.containsKey(event.name)) {
          field = event.name;
          fieldDepth = depth;
          text = StringBuffer();
        }
        if (event.isSelfClosing) finishElement();
      } else if (event is XmlEndElementEvent) {
        finishElement();
      } else if (event is XmlTextEvent) {
        text?.write(event.value);
      } else if (event is XmlCDATAEvent) {
        text?.write(event.value);
      }
    }
    for (final programs in programsByChannel.values) {
      programs.sort((a, b) => a.start.compareTo(b.start));
    }
  } catch (_) {
    // Never publish a partial feed when a malformed tail invalidates the XML.
    programsByChannel.clear();
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

// ═══════════════════════════════════════════════════════════════════
//  4-Phase Channel ID Matching
// ═══════════════════════════════════════════════════════════════════

/// Find the best matching XMLTV channel ID for a given search ID.
/// Uses a 4-phase matching algorithm:
/// 1. Exact match
/// 2. Case-insensitive match
/// 3. Prefix match (bidirectional, with dot/underscore separators)
/// 4. Normalized match (strip suffixes, remove punctuation)
String? findXmltvChannelId(String searchId, XmltvParseResult xmltv) {
  if (searchId.isEmpty) return null;

  // Phase 1: Exact match
  if (xmltv.programsByChannel.containsKey(searchId)) {
    return searchId;
  }

  // Phase 2: Case-insensitive match
  final lowerSearch = searchId.toLowerCase();
  for (final key in xmltv.programsByChannel.keys) {
    if (key.toLowerCase() == lowerSearch) return key;
  }

  // Phase 3: Prefix match (bidirectional)
  for (final key in xmltv.programsByChannel.keys) {
    final lowerKey = key.toLowerCase();
    // searchId is prefix of XMLTV key
    if (lowerKey.startsWith(lowerSearch) &&
        lowerKey.length > lowerSearch.length &&
        (lowerKey[lowerSearch.length] == '.' ||
            lowerKey[lowerSearch.length] == '_')) {
      return key;
    }
    // XMLTV key is prefix of searchId
    if (lowerSearch.startsWith(lowerKey) &&
        lowerSearch.length > lowerKey.length &&
        (lowerSearch[lowerKey.length] == '.' ||
            lowerSearch[lowerKey.length] == '_')) {
      return key;
    }
  }

  // Phase 4: Normalized match
  final normalizedSearch = normalizeChannelId(searchId);
  final match = xmltv.normalizedIndex[normalizedSearch];
  if (match != null) return match;

  return null;
}

// ═══════════════════════════════════════════════════════════════════
//  XMLTV Service (Download + Cache)
// ═══════════════════════════════════════════════════════════════════

/// One cached feed, keyed by its full URL; concurrent loads of that feed share
/// work. Expiry applies to RAM too. Clear/force prevents older responses from
/// repopulating the cache. Large raw XML is never stored in preferences.
class XmltvCache {
  final Future<XmltvParseResult?> Function(String) load;
  final DateTime Function() now;
  final Duration ttl;
  final void Function()? onClear;
  XmltvCache({
    required this.load,
    this.onClear,
    DateTime Function()? now,
    this.ttl = const Duration(hours: 6),
  }) : now = now ?? DateTime.now;
  String? _url;
  DateTime? _fetchedAt;
  XmltvParseResult? _result;
  final _pending = <String, Future<XmltvParseResult?>>{};
  int _generation = 0;

  Future<XmltvParseResult?> fetch(String url, {bool force = false}) {
    final age = _fetchedAt == null ? null : now().difference(_fetchedAt!);
    if (!force && _url == url && age != null && !age.isNegative && age < ttl) {
      return Future.value(_result);
    }
    if (!force && _pending.containsKey(url)) return _pending[url]!;
    if (force) clear();
    final generation = _generation;
    late final Future<XmltvParseResult?> future;
    future = Future.sync(() => load(url))
        .then((value) {
          if (generation == _generation &&
              value != null &&
              value.programsByChannel.isNotEmpty) {
            _url = url;
            _result = value;
            _fetchedAt = now();
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_pending[url], future)) _pending.remove(url);
        });
    _pending[url] = future;
    return future;
  }

  void clear() {
    onClear?.call();
    _generation++;
    _url = null;
    _result = null;
    _fetchedAt = null;
    _pending.clear();
  }
}

class XmltvParseCancelled implements Exception {
  const XmltvParseCancelled();
}

void _xmltvWorker((SendPort, List<int>, DateTime?) input) {
  try {
    String body;
    try {
      body = utf8.decode(input.$2);
    } on FormatException {
      body = latin1.decode(input.$2);
    }
    Isolate.exit(input.$1, parseXmltv(body, now: input.$3));
  } catch (_) {
    Isolate.exit(input.$1, 'XMLTV parse failed');
  }
}

Future<XmltvParseResult> parseXmltvBytesAsync(
  List<int> bytes, {
  DateTime? now,
  Future<void>? cancelled,
}) async {
  final port = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(
      _xmltvWorker,
      (port.sendPort, bytes, now),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    final message = await Future.any<Object?>([
      port.first,
      if (cancelled != null)
        cancelled.then<Object?>((_) => throw const XmltvParseCancelled()),
    ]);
    if (message is! XmltvParseResult)
      throw const FormatException('XMLTV parse failed');
    return message;
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

class XmltvService {
  static final _jobs = <Dio, Completer<void>>{};
  static void _cancelJobs() {
    for (final entry in _jobs.entries.toList()) {
      if (!entry.value.isCompleted) entry.value.complete();
      entry.key.close(force: true);
    }
  }

  static final _cache = XmltvCache(load: _download, onClear: _cancelJobs);
  static Future<XmltvParseResult?> fetchAndParse(
    String url, {
    bool force = false,
  }) => _cache.fetch(url, force: force);

  static Future<XmltvParseResult?> _download(String url) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'User-Agent': 'LifeOsTV/1.0'},
        responseType: ResponseType.bytes,
      ),
    );
    final cancelled = Completer<void>();
    _jobs[dio] = cancelled;
    final budget = SyncBudget.current;
    if (budget != null) {
      unawaited(
        budget.cancelToken.whenCancel.then((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        }),
      );
    }
    try {
      final response = await BoundedGetClient(
        dio,
        timeout: const Duration(seconds: 120),
        maxBytes: 64 * 1024 * 1024,
      ).get<List<int>>(url);
      if (response.statusCode != 200 || response.data == null) return null;
      final result = await parseXmltvBytesAsync(
        response.data!,
        now: DateTime.now(),
        cancelled: cancelled.future,
      );
      return result.programsByChannel.isEmpty ? null : result;
    } catch (_) {
      return null;
    } finally {
      _jobs.remove(dio);
      dio.close(force: true);
    }
  }

  static Future<void> clearCache() async {
    _cache.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('xmltv_cache_') || key.startsWith('xmltv_ts_')) {
        await prefs.remove(key);
      }
    }
  }
}
