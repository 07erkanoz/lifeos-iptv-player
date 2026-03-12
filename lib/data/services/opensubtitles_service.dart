/// OpenSubtitles REST API v1 Service
/// Port of Tauri opensubtitles.service.ts
///
/// Features:
/// - Subtitle search by query, IMDB ID, language, season/episode
/// - Download with SRT → VTT conversion
/// - In-memory cache (10 min TTL)
/// - Rate limiting awareness

import 'dart:convert';
import 'package:dio/dio.dart';

// ═══════════════════════════════════════════════════════════════════
//  Models
// ═══════════════════════════════════════════════════════════════════

class ExternalSubtitle {
  final String id;
  final int fileId;
  final String language;
  final String languageLabel;
  final String? release;
  final String? fileName;
  final int downloadCount;
  final bool aiTranslated;
  final bool hearingImpaired;
  final bool trusted;
  final double rating;

  const ExternalSubtitle({
    required this.id,
    required this.fileId,
    required this.language,
    required this.languageLabel,
    this.release,
    this.fileName,
    this.downloadCount = 0,
    this.aiTranslated = false,
    this.hearingImpaired = false,
    this.trusted = false,
    this.rating = 0,
  });
}

class SubtitleDownloadResult {
  final String content; // VTT content
  final String fileName;
  final int remainingDownloads;

  const SubtitleDownloadResult({
    required this.content,
    required this.fileName,
    this.remainingDownloads = 0,
  });
}

class SubtitleSearchParams {
  final String? query;
  final String? imdbId;
  final String? tmdbId;
  final String languages;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final String type; // 'movie', 'episode', 'all'

  const SubtitleSearchParams({
    this.query,
    this.imdbId,
    this.tmdbId,
    this.languages = 'tr,en',
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.type = 'all',
  });
}

// ═══════════════════════════════════════════════════════════════════
//  Language Labels
// ═══════════════════════════════════════════════════════════════════

const _languageLabels = <String, String>{
  'tr': 'Türkçe',
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'ar': 'العربية',
  'ru': 'Русский',
  'ku': 'Kurdî',
  'pt-br': 'Português (BR)',
  'pt-pt': 'Português',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'ro': 'Română',
  'el': 'Ελληνικά',
  'hu': 'Magyar',
  'cs': 'Čeština',
  'bg': 'Български',
  'hr': 'Hrvatski',
  'sr': 'Srpski',
  'uk': 'Українська',
  'sv': 'Svenska',
  'no': 'Norsk',
  'da': 'Dansk',
  'fi': 'Suomi',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh-cn': 'Chinese (Simplified)',
  'zh-tw': 'Chinese (Traditional)',
  'vi': 'Tiếng Việt',
  'th': 'Thai',
  'id': 'Indonesian',
  'ms': 'Malay',
  'hi': 'Hindi',
  'he': 'Hebrew',
  'fa': 'فارسی',
};

// ═══════════════════════════════════════════════════════════════════
//  SRT → VTT Conversion
// ═══════════════════════════════════════════════════════════════════

/// Convert SRT subtitle content to WebVTT format.
/// - Replaces commas with periods in timestamps
/// - Removes sequence numbers
/// - Adds WEBVTT header
String srtToVtt(String srt) {
  var vtt = 'WEBVTT\n\n';
  vtt += srt
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      // Comma → Period for milliseconds (00:01:23,456 → 00:01:23.456)
      .replaceAllMapped(
        RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})'),
        (m) => '${m[1]}.${m[2]}',
      )
      // Remove SRT sequence numbers (standalone digits on a line)
      .replaceAll(RegExp(r'^\d+\n', multiLine: true), '')
      .trim();
  return vtt;
}

// ═══════════════════════════════════════════════════════════════════
//  OpenSubtitles Service
// ═══════════════════════════════════════════════════════════════════

class OpenSubtitlesService {
  static const _baseUrl = 'https://api.opensubtitles.com';
  static const _cacheTtl = Duration(minutes: 10);

  final String apiKey;
  final Dio _dio;

  /// In-memory search cache
  final Map<String, ({List<ExternalSubtitle> results, DateTime ts})> _cache = {};

  OpenSubtitlesService(this.apiKey)
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Api-Key': apiKey,
            'User-Agent': 'LifeOSTV v1.0.0',
            'Content-Type': 'application/json',
          },
        ));

  /// Singleton management
  static OpenSubtitlesService? _instance;
  static String? _instanceKey;

  static OpenSubtitlesService? getInstance(String? apiKey) {
    if (apiKey == null || apiKey.isEmpty) return null;
    if (_instance != null && _instanceKey == apiKey) return _instance;
    _instance = OpenSubtitlesService(apiKey);
    _instanceKey = apiKey;
    return _instance;
  }

  // ─── Search ───────────────────────────────────────────────────────────

  /// Search for subtitles using OpenSubtitles API v1
  Future<List<ExternalSubtitle>> search(SubtitleSearchParams params) async {
    // Build cache key
    final cacheKey = '${params.query}_${params.imdbId}_${params.languages}_'
        '${params.seasonNumber}_${params.episodeNumber}_${params.year}_${params.type}';

    // Check cache
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.ts) < _cacheTtl) {
      return cached.results;
    }

    try {
      final queryParams = <String, dynamic>{
        'languages': params.languages,
        'machine_translated': 'exclude',
      };

      if (params.query != null && params.query!.isNotEmpty) {
        queryParams['query'] = params.query;
      }
      if (params.imdbId != null && params.imdbId!.isNotEmpty) {
        queryParams['imdb_id'] = params.imdbId;
      }
      if (params.tmdbId != null && params.tmdbId!.isNotEmpty) {
        queryParams['tmdb_id'] = params.tmdbId;
      }
      if (params.seasonNumber != null) {
        queryParams['season_number'] = params.seasonNumber;
      }
      if (params.episodeNumber != null) {
        queryParams['episode_number'] = params.episodeNumber;
      }
      if (params.year != null) {
        queryParams['year'] = params.year;
      }
      if (params.type != 'all') {
        queryParams['type'] = params.type;
      }

      final response = await _dio.get(
        '/api/v1/subtitles',
        queryParameters: queryParams,
      );

      if (response.statusCode != 200 || response.data == null) return [];

      final data = response.data as Map<String, dynamic>;
      final dataList = data['data'] as List<dynamic>? ?? [];

      final results = <ExternalSubtitle>[];
      for (final item in dataList) {
        final attrs = item['attributes'] as Map<String, dynamic>? ?? {};
        final files = attrs['files'] as List<dynamic>? ?? [];
        if (files.isEmpty) continue;

        final file = files[0] as Map<String, dynamic>;
        final lang = attrs['language']?.toString() ?? 'en';

        results.add(ExternalSubtitle(
          id: item['id']?.toString() ?? '',
          fileId: int.tryParse(file['file_id']?.toString() ?? '') ?? 0,
          language: lang,
          languageLabel: _languageLabels[lang] ?? lang,
          release: attrs['release']?.toString(),
          fileName: file['file_name']?.toString(),
          downloadCount: int.tryParse(attrs['download_count']?.toString() ?? '') ?? 0,
          aiTranslated: attrs['ai_translated'] == true,
          hearingImpaired: attrs['hearing_impaired'] == true,
          trusted: attrs['from_trusted'] == true,
          rating: double.tryParse(attrs['ratings']?.toString() ?? '') ?? 0,
        ));
      }

      // Sort: trusted first, then by download count
      results.sort((a, b) {
        if (a.trusted != b.trusted) return b.trusted ? 1 : -1;
        return b.downloadCount.compareTo(a.downloadCount);
      });

      // Cache results
      _cache[cacheKey] = (results: results, ts: DateTime.now());

      return results;
    } catch (_) {
      return [];
    }
  }

  // ─── Download ────────────────────────────────────────────────────────

  /// Download a subtitle file and return its content as VTT
  Future<SubtitleDownloadResult?> download(int fileId) async {
    try {
      // Step 1: Get download link
      final linkResponse = await _dio.post(
        '/api/v1/download',
        data: jsonEncode({'file_id': fileId}),
      );

      if (linkResponse.statusCode != 200 || linkResponse.data == null) return null;

      final linkData = linkResponse.data as Map<String, dynamic>;
      final downloadUrl = linkData['link']?.toString();
      final fileName = linkData['file_name']?.toString() ?? 'subtitle.srt';
      final remaining = int.tryParse(linkData['remaining']?.toString() ?? '') ?? 0;

      if (downloadUrl == null || downloadUrl.isEmpty) return null;

      // Step 2: Download the actual file
      final fileResponse = await Dio().get<List<int>>(
        downloadUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (fileResponse.data == null) return null;

      // Decode content
      String content;
      try {
        content = utf8.decode(fileResponse.data!);
      } catch (_) {
        content = latin1.decode(fileResponse.data!);
      }

      // Convert SRT to VTT if needed
      if (fileName.endsWith('.srt') || !content.startsWith('WEBVTT')) {
        content = srtToVtt(content);
      }

      return SubtitleDownloadResult(
        content: content,
        fileName: fileName.replaceAll('.srt', '.vtt'),
        remainingDownloads: remaining,
      );
    } catch (_) {
      return null;
    }
  }

  /// Clear the search cache
  void clearCache() {
    _cache.clear();
  }
}
