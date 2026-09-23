/// XMLTV Parser Service
/// Tauri epg.service.ts'den port edilmiştir.
///
/// Desteklenen özellikler:
/// - XMLTV XML parse (programme/channel elementleri)
/// - Kanal ID normalizasyonu (lowercase, noktalama kaldır, .tr/.com.tr suffix strip)
/// - 4 aşamalı eşleştirme: exact → case-insensitive → prefix → normalized
/// - 6 saat TTL ile cache
library;

import 'dart:convert';
import 'dart:isolate';
import 'bounded_get_client.dart';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
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
  XmltvCache({
    required this.load,
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
    _generation++;
    _url = null;
    _result = null;
    _fetchedAt = null;
    _pending.clear();
  }
}

Future<XmltvParseResult> parseXmltvBytesAsync(
  List<int> bytes, {
  DateTime? now,
}) => Isolate.run(() {
  String body;
  try {
    body = utf8.decode(bytes);
  } on FormatException {
    body = latin1.decode(bytes);
  }
  return parseXmltv(body, now: now);
});

class XmltvService {
  static final _cache = XmltvCache(load: _download);
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
      );
      return result.programsByChannel.isEmpty ? null : result;
    } catch (_) {
      return null;
    } finally {
      dio.close();
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
