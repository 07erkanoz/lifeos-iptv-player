/// M3U/M3U8 Parser Service
/// Tauri m3u.service.ts'den port edilmiştir.
///
/// Desteklenen formatlar:
/// - Standart M3U (#EXTINF + URL)
/// - Basit M3U (sadece URL satırları)
/// - #EXTGRP directive (Kodi pvr.iptvsimple standardı)
/// - Sticky group-title davranışı
/// - 7 protokol: http, https, rtsp, rtmp, udp, rtp, mms

import 'dart:convert';
import 'package:dio/dio.dart';

// ═══════════════════════════════════════════════════════════════════
//  Veri Modelleri
// ═══════════════════════════════════════════════════════════════════

class M3UEntry {
  final String name;
  final int duration;
  final String? tvgId;
  final String? tvgName;
  final String? tvgLogo;
  final String? tvgType;
  final String? groupTitle;
  final String url;
  final Map<String, String> extras;

  const M3UEntry({
    required this.name,
    this.duration = -1,
    this.tvgId,
    this.tvgName,
    this.tvgLogo,
    this.tvgType,
    this.groupTitle,
    required this.url,
    this.extras = const {},
  });
}

class M3UCategory {
  final String id;
  final String name;
  final String type; // 'live', 'movie', 'series'

  const M3UCategory({required this.id, required this.name, required this.type});
}

class M3UParseResult {
  final List<M3UEntry> entries;
  final List<M3UCategory> categories;
  final int liveCount;
  final int movieCount;
  final int seriesCount;
  final String? epgUrl; // url-tvg from #EXTM3U header

  const M3UParseResult({
    required this.entries,
    required this.categories,
    this.liveCount = 0,
    this.movieCount = 0,
    this.seriesCount = 0,
    this.epgUrl,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  URL Doğrulama
// ═══════════════════════════════════════════════════════════════════

const _validProtocols = [
  'http://', 'https://', 'rtsp://', 'rtmp://', 'udp://', 'rtp://', 'mms://',
];

bool _isValidStreamUrl(String url) {
  if (url.isEmpty) return false;
  if (url.startsWith('/') && url.length > 1) return true;
  return url.length > 8 && _validProtocols.any((p) => url.startsWith(p));
}

bool _isDummyUrl(String url) {
  final lower = url.toLowerCase();
  if (lower == 'http://blank' || lower == 'https://blank') return true;
  if (lower == 'http://localhost' || lower == 'https://localhost') return true;
  if (lower == 'http://0.0.0.0' || lower == 'https://0.0.0.0') return true;
  if (url.length < 20) {
    if (lower.endsWith('/blank') || lower.endsWith('/null') || lower.endsWith('/none')) {
      return true;
    }
  }
  return false;
}

final _separatorRegex = RegExp(r'^[-=*~#]{3}');

bool _isSeparatorName(String name) {
  return _separatorRegex.hasMatch(name);
}

// ═══════════════════════════════════════════════════════════════════
//  Stream Type Sınıflandırma (Score-based)
// ═══════════════════════════════════════════════════════════════════

final _seriesEpisodeRegex = RegExp(r'S\d{1,2}\s?E\d{1,2}', caseSensitive: false);
final _seriesAltRegex = RegExp(r'\d{1,2}x\d{1,2}', caseSensitive: false);

String classifyStreamType({
  required String url,
  String? name,
  String? tvgType,
  String? groupTitle,
}) {
  int liveScore = 0;
  int movieScore = 0;
  int seriesScore = 0;

  // 1) tvg-type attribute — en güçlü sinyal (+5)
  if (tvgType != null && tvgType.isNotEmpty) {
    final t = tvgType.toLowerCase();
    if (t == 'live' || t == 'livetv' || t == 'radio') {
      liveScore += 5;
    } else if (t == 'movie' || t == 'vod') {
      movieScore += 5;
    } else if (t == 'series' || t == 'serie' || t == 'tvshow') {
      seriesScore += 5;
    }
  }

  final lowerUrl = url.toLowerCase();

  // 2) URL path — Xtream API pattern (+3)
  if (lowerUrl.contains('/live/')) liveScore += 3;
  if (lowerUrl.contains('/movie/')) movieScore += 3;
  if (lowerUrl.contains('/series/')) seriesScore += 3;

  // 3) Dosya uzantısı (+2)
  if (lowerUrl.endsWith('.mp4') || lowerUrl.endsWith('.mkv') || lowerUrl.endsWith('.avi')) {
    movieScore += 2;
  } else if (lowerUrl.endsWith('.ts') || lowerUrl.endsWith('.m3u8')) {
    liveScore += 1;
  }

  // 4) Kanal adı — dizi episod pattern (+3)
  if (name != null && name.isNotEmpty) {
    if (_seriesEpisodeRegex.hasMatch(name) || _seriesAltRegex.hasMatch(name)) {
      seriesScore += 3;
    }
  }

  // 5) Group title keyword (+1)
  if (groupTitle != null && groupTitle.isNotEmpty) {
    final g = groupTitle.toLowerCase();
    if (g.contains('vod') || g.contains('movie') || g.contains('film')) movieScore += 1;
    if (g.contains('series') || g.contains('dizi')) seriesScore += 1;
  }

  if (movieScore > liveScore && movieScore > seriesScore) return 'movie';
  if (seriesScore > liveScore && seriesScore > movieScore) return 'series';
  return 'live';
}

// ═══════════════════════════════════════════════════════════════════
//  EXTINF Satır Parser
// ═══════════════════════════════════════════════════════════════════

final _durationRegex = RegExp(r'#EXTINF:(-?[\d.]+)');
final _attrRegex = RegExp(r'([\w-]+)=["\x27]([^"\x27]*)["\x27]');
final _nameRegex = RegExp(r',\s*(.+)$');

({
  String name,
  int duration,
  String? tvgId,
  String? tvgName,
  String? tvgLogo,
  String? tvgType,
  String? groupTitle,
  Map<String, String> extras,
}) _parseExtInf(String line) {
  final extras = <String, String>{};

  // Duration
  final durationMatch = _durationRegex.firstMatch(line);
  final duration = durationMatch != null ? int.tryParse(durationMatch.group(1)!) ?? -1 : -1;

  // Attributes
  for (final match in _attrRegex.allMatches(line)) {
    extras[match.group(1)!] = match.group(2)!;
  }

  // Channel name
  final nameMatch = _nameRegex.firstMatch(line);
  var name = nameMatch?.group(1)?.trim() ?? '';

  if (name.isEmpty) {
    name = extras['tvg-name'] ?? extras['tvg-Name'] ?? '';
  }

  return (
    name: name,
    duration: duration,
    tvgId: extras['tvg-id'] ?? extras['tvg-ID'],
    tvgName: extras['tvg-name'] ?? extras['tvg-Name'],
    tvgLogo: extras['tvg-logo'] ?? extras['tvg-Logo'],
    tvgType: extras['tvg-type'] ?? extras['tvg-Type'] ?? extras['type'],
    groupTitle: extras['group-title'] ?? extras['group-Title'],
    extras: extras,
  );
}

// ═══════════════════════════════════════════════════════════════════
//  Ana Parser
// ═══════════════════════════════════════════════════════════════════

/// M3U içeriğini parse eder.
/// Kodi pvr.iptvsimple standardına uygun:
/// - group-title sticky davranışı
/// - #EXTGRP begin directive
/// - Dummy URL filtreleme
/// - Basit M3U (EXTINF'siz URL'ler) desteği
/// Parse result including the raw entry list and optional EPG URL from header
class M3URawResult {
  final List<M3UEntry> entries;
  final String? epgUrl;
  const M3URawResult({required this.entries, this.epgUrl});
}

/// Extract url-tvg from #EXTM3U header line
String? _extractEpgUrl(String headerLine) {
  // Match: url-tvg="..." or url-tvg='...'
  final match = RegExp(r'url-tvg=["\x27]([^"\x27]+)["\x27]').firstMatch(headerLine);
  return match?.group(1);
}

M3URawResult parseM3URaw(String content) {
  final normalizedContent = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalizedContent.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final entries = <M3UEntry>[];

  if (lines.isEmpty) return M3URawResult(entries: entries);

  // Extract EPG URL from #EXTM3U header
  String? epgUrl;

  // Sticky gruplama state
  var lastGroupTitle = '';
  var extgrpDirective = '';
  var groupsFromExtgrpDirective = false;

  // #EXTM3U başlığını atla
  var i = 0;
  if (lines[0].startsWith('#EXTM3U')) {
    epgUrl = _extractEpgUrl(lines[0]);
    i = 1;
  }

  while (i < lines.length) {
    final line = lines[i];

    // Bağımsız #EXTGRP satırları (EXTINF öncesi)
    if (line.startsWith('#EXTGRP:') && !line.startsWith('#EXTINF:')) {
      final grp = line.substring(8).trim();
      if (grp.isNotEmpty) {
        extgrpDirective = grp;
        groupsFromExtgrpDirective = true;
      } else {
        extgrpDirective = '';
        groupsFromExtgrpDirective = false;
      }
      i++;
      continue;
    }

    if (line.startsWith('#EXTINF:')) {
      final info = _parseExtInf(line);
      var groupTitle = info.groupTitle;

      // Ek # satırlarını tara
      i++;
      while (i < lines.length && lines[i].startsWith('#')) {
        final extraLine = lines[i];
        if (extraLine.startsWith('#EXTGRP:')) {
          final grp = extraLine.substring(8).trim();
          if (grp.isNotEmpty) {
            extgrpDirective = grp;
            groupsFromExtgrpDirective = true;
            groupTitle ??= grp;
          } else {
            extgrpDirective = '';
            groupsFromExtgrpDirective = false;
          }
        }
        i++;
      }

      // Gruplama çözümleme (öncelik sırası)
      if (groupTitle != null && groupTitle.isNotEmpty) {
        lastGroupTitle = groupTitle;
        groupsFromExtgrpDirective = false;
      } else if (groupsFromExtgrpDirective && extgrpDirective.isNotEmpty) {
        groupTitle = extgrpDirective;
      } else {
        groupTitle = lastGroupTitle;
      }

      // URL satırı
      if (i < lines.length && !lines[i].startsWith('#')) {
        final url = lines[i].trim();
        if (_isValidStreamUrl(url) &&
            !_isDummyUrl(url) &&
            !(_isSeparatorName(info.name) && url.length < 25)) {
          entries.add(M3UEntry(
            name: info.name,
            duration: info.duration,
            tvgId: info.tvgId,
            tvgName: info.tvgName,
            tvgLogo: info.tvgLogo,
            tvgType: info.tvgType,
            groupTitle: groupTitle?.isNotEmpty == true ? groupTitle : null,
            url: url,
            extras: info.extras,
          ));
        }
      }
    } else if (!line.startsWith('#')) {
      // Basit M3U formatı — EXTINF olmadan düz URL
      final url = line.trim();
      if (_isValidStreamUrl(url) && !_isDummyUrl(url)) {
        final currentGroup = (groupsFromExtgrpDirective && extgrpDirective.isNotEmpty)
            ? extgrpDirective
            : lastGroupTitle;
        entries.add(M3UEntry(
          name: url,
          duration: -1,
          url: url,
          groupTitle: currentGroup.isNotEmpty ? currentGroup : null,
        ));
      }
    }
    i++;
  }

  return M3URawResult(entries: entries, epgUrl: epgUrl);
}

/// Backward-compatible wrapper that returns just entries
List<M3UEntry> parseM3U(String content) {
  return parseM3URaw(content).entries;
}

// ═══════════════════════════════════════════════════════════════════
//  URL'den M3U İndirme
// ═══════════════════════════════════════════════════════════════════

/// URL'den M3U dosyasını indir ve parse et (raw result with epgUrl)
Future<M3URawResult> parseM3UFromUrlRaw(String url) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {'User-Agent': 'LifeOsTV/1.0'},
    responseType: ResponseType.bytes,
  ));

  final response = await dio.get<List<int>>(url);

  if (response.statusCode != 200) {
    throw Exception('M3U dosyası indirilemedi (HTTP ${response.statusCode})');
  }

  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) {
    throw Exception('M3U dosyası boş');
  }

  // Body encoding — try UTF-8 first, fallback to latin1
  String body;
  try {
    body = utf8.decode(bytes);
  } catch (_) {
    body = latin1.decode(bytes);
  }

  if (body.trim().isEmpty) {
    throw Exception('M3U dosyası boş');
  }

  final result = parseM3URaw(body);
  if (result.entries.isEmpty) {
    throw Exception('M3U dosyasında kanal bulunamadı');
  }

  return result;
}

/// URL'den M3U dosyasını indir ve parse et (backward-compatible)
Future<List<M3UEntry>> parseM3UFromUrl(String url) async {
  final result = await parseM3UFromUrlRaw(url);
  return result.entries;
}

// ═══════════════════════════════════════════════════════════════════
//  Gruptan Tür Belirleme (Majority Voting)
// ═══════════════════════════════════════════════════════════════════

/// İlk 10 kanalın çoğunluk oylamasıyla grup türünü belirler
String _guessGroupStreamType(List<M3UEntry> groupEntries) {
  final sampleSize = groupEntries.length < 10 ? groupEntries.length : 10;
  final votes = {'live': 0, 'movie': 0, 'series': 0};

  for (var i = 0; i < sampleSize; i++) {
    final e = groupEntries[i];
    final result = classifyStreamType(
      url: e.url,
      name: e.name,
      tvgType: e.tvgType,
      groupTitle: e.groupTitle,
    );
    votes[result] = (votes[result] ?? 0) + 1;
  }

  if (votes['movie']! >= votes['live']! && votes['movie']! >= votes['series']!) return 'movie';
  if (votes['series']! >= votes['live']! && votes['series']! >= votes['movie']!) return 'series';
  return 'live';
}

// ═══════════════════════════════════════════════════════════════════
//  M3UEntry → Kanal/Kategori Dönüşümü
// ═══════════════════════════════════════════════════════════════════

/// M3U entry'lerden gruplara göre kategoriler oluşturur
List<M3UCategory> extractCategories(List<M3UEntry> entries) {
  final groups = <String, List<M3UEntry>>{};

  for (final entry in entries) {
    final group = entry.groupTitle ?? 'Diğer';
    groups.putIfAbsent(group, () => []).add(entry);
  }

  final categories = <M3UCategory>[];
  for (final entry in groups.entries) {
    final streamType = _guessGroupStreamType(entry.value);
    categories.add(M3UCategory(
      id: entry.key,
      name: entry.key,
      type: streamType,
    ));
  }

  return categories;
}

/// Parse sonuçlarını istatistiklerle birlikte döndürür
M3UParseResult buildParseResult(List<M3UEntry> entries, {String? epgUrl}) {
  final categories = extractCategories(entries);

  int liveCount = 0, movieCount = 0, seriesCount = 0;
  for (final entry in entries) {
    final type = classifyStreamType(
      url: entry.url,
      name: entry.name,
      tvgType: entry.tvgType,
      groupTitle: entry.groupTitle,
    );
    switch (type) {
      case 'live': liveCount++;
      case 'movie': movieCount++;
      case 'series': seriesCount++;
    }
  }

  return M3UParseResult(
    entries: entries,
    categories: categories,
    liveCount: liveCount,
    movieCount: movieCount,
    seriesCount: seriesCount,
    epgUrl: epgUrl,
  );
}
