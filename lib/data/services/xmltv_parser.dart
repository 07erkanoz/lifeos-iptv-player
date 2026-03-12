/// XMLTV Parser Service
/// Tauri epg.service.ts'den port edilmiştir.
///
/// Desteklenen özellikler:
/// - XMLTV XML parse (programme/channel elementleri)
/// - Kanal ID normalizasyonu (lowercase, noktalama kaldır, .tr/.com.tr suffix strip)
/// - 4 aşamalı eşleştirme: exact → case-insensitive → prefix → normalized
/// - 6 saat TTL ile cache

import 'dart:convert';
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
    final ts = parts[0].replaceAll(RegExp(r'[^0-9]'), '');

    if (ts.length < 14) return null;

    final year = int.parse(ts.substring(0, 4));
    final month = int.parse(ts.substring(4, 6));
    final day = int.parse(ts.substring(6, 8));
    final hour = int.parse(ts.substring(8, 10));
    final minute = int.parse(ts.substring(10, 12));
    final second = int.parse(ts.substring(12, 14));

    // Parse timezone offset if present (e.g. "+0300")
    if (parts.length > 1) {
      final tzStr = parts[1];
      final tzMatch = RegExp(r'([+-])(\d{2})(\d{2})').firstMatch(tzStr);
      if (tzMatch != null) {
        final sign = tzMatch.group(1) == '+' ? 1 : -1;
        final tzHours = int.parse(tzMatch.group(2)!);
        final tzMinutes = int.parse(tzMatch.group(3)!);
        final offset = Duration(hours: tzHours, minutes: tzMinutes) * sign;
        // Create UTC time by subtracting the offset, then convert to local
        return DateTime.utc(year, month, day, hour, minute, second)
            .subtract(offset)
            .toLocal();
      }
    }

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
XmltvParseResult parseXmltv(String xmlContent) {
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
      if (start == null || stop == null) continue;

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

      programsByChannel.putIfAbsent(channelId, () => []).add(
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
String? findXmltvChannelId(
  String searchId,
  XmltvParseResult xmltv,
) {
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

class XmltvService {
  static const _ttl = Duration(hours: 6);
  static const _cachePrefix = 'xmltv_cache_';
  static const _cacheTimestampPrefix = 'xmltv_ts_';

  /// In-memory cache
  static XmltvParseResult? _cachedResult;
  static String? _cachedUrl;

  /// Fetch and parse XMLTV data from URL.
  /// Uses in-memory + SharedPreferences cache with 6-hour TTL.
  static Future<XmltvParseResult?> fetchAndParse(String xmltvUrl) async {
    // In-memory cache hit
    if (_cachedResult != null && _cachedUrl == xmltvUrl) {
      return _cachedResult;
    }

    // Check SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTs = prefs.getInt('${_cacheTimestampPrefix}hash') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - cachedTs < _ttl.inMilliseconds) {
        // Try loading from cache
        final cachedXml = prefs.getString('${_cachePrefix}data');
        if (cachedXml != null && cachedXml.isNotEmpty) {
          final result = parseXmltv(cachedXml);
          if (result.programsByChannel.isNotEmpty) {
            _cachedResult = result;
            _cachedUrl = xmltvUrl;
            return result;
          }
        }
      }
    } catch (_) {}

    // Fetch from URL
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120), // XMLTV can be large
        headers: {'User-Agent': 'LifeOsTV/1.0'},
        responseType: ResponseType.bytes,
      ));

      final response = await dio.get<List<int>>(xmltvUrl);
      if (response.statusCode != 200 || response.data == null) return null;

      // Decode body
      String xmlContent;
      try {
        xmlContent = utf8.decode(response.data!);
      } catch (_) {
        xmlContent = latin1.decode(response.data!);
      }

      if (xmlContent.trim().isEmpty) return null;

      final result = parseXmltv(xmlContent);
      if (result.programsByChannel.isEmpty) return null;

      // Cache to memory
      _cachedResult = result;
      _cachedUrl = xmltvUrl;

      // Async save to SharedPreferences (non-blocking)
      // Only save if reasonably sized (< 5MB)
      if (xmlContent.length < 5 * 1024 * 1024) {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString('${_cachePrefix}data', xmlContent);
          prefs.setInt(
            '${_cacheTimestampPrefix}hash',
            DateTime.now().millisecondsSinceEpoch,
          );
        });
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// Clear cached XMLTV data
  static Future<void> clearCache() async {
    _cachedResult = null;
    _cachedUrl = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_cachePrefix}data');
      await prefs.remove('${_cacheTimestampPrefix}hash');
    } catch (_) {}
  }
}
