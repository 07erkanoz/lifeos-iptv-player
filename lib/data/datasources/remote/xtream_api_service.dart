import 'dart:async';
import 'package:lifeostv/data/services/bounded_get_client.dart';
import 'package:lifeostv/data/services/sync_budget.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/data/services/api_queue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'xtream_api_service.g.dart';

/// Redact username/password query parameters from any URL-ish string so
/// we never print Xtream credentials into logs or bubble them up in error
/// messages shown to the user.
String _sanitize(Object? raw) {
  if (raw == null) return '';
  final s = raw.toString();
  return s
      .replaceAll(RegExp(r'(username=)[^&\s]+', caseSensitive: false), r'$1***')
      .replaceAll(
        RegExp(r'(password=)[^&\s]+', caseSensitive: false),
        r'$1***',
      );
}

class XtreamApiService {
  final BoundedGetClient _client;
  final ApiCache _cache = ApiCache.instance;
  final ApiQueue _queue = ApiQueue.instance;

  XtreamApiService(Dio dio) : _client = BoundedGetClient(dio);

  Future<T> _enqueue<T>(
    String key,
    Future<T> Function() request, {
    ApiPriority priority = ApiPriority.normal,
  }) {
    final budget = SyncBudget.current;
    final bound = Zone.current.bindCallback(() async {
      budget?.check();
      return request();
    });
    return _queue.enqueue(key, bound, priority: priority);
  }

  /// Account-scoped prefix for cache + queue keys.
  ///
  /// Previously the cache keys were just `vod_info_$vodId` /
  /// `series_info_$seriesId` / `epg_$streamId` — so two different
  /// servers that happened to share a stream id (very common with
  /// public Xtream panels) would clobber each other's cached
  /// responses. After a user switched accounts, VOD info / EPG could
  /// come back wrong.
  ///
  /// The format `username@normalisedUrl:` matches what the rest of
  /// the app uses for `ApiCache.invalidateForAccount(...)`, so
  /// invalidation still works the same way.
  String _scope(String url, String username) {
    final normalised = url.replaceAll(RegExp(r'/+$'), '');
    return '$username@$normalised:';
  }

  /// Normalize URL: extract base server URL from various formats
  /// Handles: http://host:port, http://host:port/player_api.php?...,
  /// http://host:port/get.php?..., full m3u links, etc.
  static String normalizeUrl(String url) {
    final raw = url.trim();
    final uri = Uri.parse(raw.contains('://') ? raw : 'http://$raw');
    if (!const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Invalid server address');
    }
    final segments = uri.pathSegments.toList();
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.isNotEmpty &&
        const {
          'player_api.php',
          'get.php',
          'xmltv.php',
        }.contains(segments.last.toLowerCase())) {
      segments.removeLast();
    } else if (segments.length >= 4 &&
        const {
          'live',
          'movie',
          'series',
        }.contains(segments[segments.length - 4])) {
      segments.removeRange(segments.length - 4, segments.length);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
    ).toString().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> authenticate(
    String url,
    String username,
    String password,
  ) async {
    final fullUrl = normalizeUrl(url);

    try {
      final response = await _client.get(
        '$fullUrl/player_api.php',
        queryParameters: {'username': username, 'password': password},
        options: Options(responseType: ResponseType.json),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['user_info'] != null) {
          if (data['user_info']['auth'] == 1) {
            return data;
          }
          throw Exception(
            'Invalid credentials: authentication denied by server',
          );
        }
        throw Exception('Invalid server response: missing user_info');
      }
      throw Exception('Server returned status ${response.statusCode}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception(
          'Connection timeout: server at $fullUrl is not responding',
        );
      } else if (e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Cannot connect to server: $fullUrl - check URL and port',
        );
      } else if (e.response?.statusCode == 403) {
        throw Exception('Access denied (403): server blocked the request');
      } else if (e.response?.statusCode == 404) {
        throw Exception(
          'Server not found (404): $fullUrl may not be an Xtream server',
        );
      }
      throw Exception('Connection error: ${_sanitize(e.message)}');
    }
  }

  Future<List<dynamic>> getCategories(
    String url,
    String username,
    String password,
    String action,
  ) async {
    final cacheKey = '${_scope(url, username)}cat_$action';
    final cached = _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _enqueue<List<dynamic>>(cacheKey, () async {
      final response = await _client.get(
        '$url/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          'action': action,
        },
      );
      if (response.data is List) return response.data as List<dynamic>;
      throw const FormatException('Expected a catalogue list');
    }, priority: ApiPriority.normal);
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.categoriesTtl);
    }
    return result;
  }

  Future<List<dynamic>> getStreams(
    String url,
    String username,
    String password,
    String action, {
    String? categoryId,
  }) async {
    final cacheKey =
        '${_scope(url, username)}streams_${action}_${categoryId ?? 'all'}';
    final cached = _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _enqueue<List<dynamic>>(cacheKey, () async {
      final Map<String, dynamic> query = {
        'username': username,
        'password': password,
        'action': action,
      };
      if (categoryId != null) query['category_id'] = categoryId;

      final response = await _client.get(
        '$url/player_api.php',
        queryParameters: query,
      );
      if (response.data is List) return response.data as List<dynamic>;
      throw const FormatException('Expected a catalogue list');
    }, priority: ApiPriority.normal);
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.streamsTtl);
    }
    return result;
  }

  /// Get VOD (movie) detail info: plot, cast, genre, director, duration, backdrop
  /// Uses cache (30 min TTL) + queue (max 1 concurrent request)
  Future<Map<String, dynamic>?> getVODInfo(
    String url,
    String username,
    String password,
    int vodId,
  ) async {
    final cacheKey = '${_scope(url, username)}vod_info_$vodId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _enqueue<Map<String, dynamic>?>(cacheKey, () async {
        final response = await _client.get(
          '$url/player_api.php',
          queryParameters: {
            'username': username,
            'password': password,
            'action': 'get_vod_info',
            'vod_id': vodId,
          },
        );
        if (response.data is Map) return response.data as Map<String, dynamic>;
        return null;
      }, priority: ApiPriority.high);
      if (result != null) {
        _cache.set(cacheKey, result, ApiCache.vodInfoTtl);
      }
      return result;
    } catch (e) {
      debugPrint('[XtreamApi] getVODInfo($vodId) failed: ${_sanitize(e)}');
    }
    return null;
  }

  /// Get Series info: seasons, episodes with details
  /// Uses cache (30 min TTL) + queue (max 1 concurrent request)
  Future<Map<String, dynamic>?> getSeriesInfo(
    String url,
    String username,
    String password,
    int seriesId,
  ) async {
    final cacheKey = '${_scope(url, username)}series_info_$seriesId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _enqueue<Map<String, dynamic>?>(cacheKey, () async {
        final response = await _client.get(
          '$url/player_api.php',
          queryParameters: {
            'username': username,
            'password': password,
            'action': 'get_series_info',
            'series_id': seriesId,
          },
        );
        if (response.data is Map) return response.data as Map<String, dynamic>;
        return null;
      }, priority: ApiPriority.high);
      if (result != null) {
        _cache.set(cacheKey, result, ApiCache.seriesInfoTtl);
      }
      return result;
    } catch (e) {
      debugPrint(
        '[XtreamApi] getSeriesInfo($seriesId) failed: ${_sanitize(e)}',
      );
    }
    return null;
  }

  /// Get short EPG for a single stream (default 20 listings)
  /// Uses cache (15 min TTL) + queue
  Future<Map<String, dynamic>> getEpg(
    String url,
    String username,
    String password,
    String streamId, {
    int? limit,
  }) async {
    final cacheKey = '${_scope(url, username)}epg_$streamId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _enqueue<Map<String, dynamic>>(cacheKey, () async {
      final response = await _client.get(
        '$url/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          'action': 'get_short_epg',
          'stream_id': streamId,
          'limit': limit ?? 20,
        },
      );
      if (response.data is Map) return response.data as Map<String, dynamic>;
      return <String, dynamic>{};
    }, priority: ApiPriority.normal);
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.epgTtl);
    }
    return result;
  }

  /// Get full EPG table for all streams (or a single stream)
  /// Uses cache (15 min TTL) + queue
  Future<Map<String, dynamic>> getAllEpg(
    String url,
    String username,
    String password, {
    String? streamId,
  }) async {
    final cacheKey = streamId != null
        ? '${_scope(url, username)}all_epg_$streamId'
        : '${_scope(url, username)}all_epg';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _enqueue<Map<String, dynamic>>(cacheKey, () async {
      final Map<String, dynamic> query = {
        'username': username,
        'password': password,
        'action': 'get_simple_data_table',
      };
      if (streamId != null) query['stream_id'] = streamId;

      final response = await _client.get(
        '$url/player_api.php',
        queryParameters: query,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      if (response.data is Map) return response.data as Map<String, dynamic>;
      return <String, dynamic>{};
    }, priority: ApiPriority.normal);
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.epgAllTtl);
    }
    return result;
  }
}

@riverpod
XtreamApiService xtreamApiService(Ref ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'LifeOsTV/1.0'},
    ),
  );

  // Decode every response (get_vod_streams / get_series can be MANY MB
  // / thousands of items) in a background isolate instead of jsonDecode
  // on the UI thread. Keeps the app fluid during a full catalogue sync.
  dio.transformer = BackgroundTransformer();

  return XtreamApiService(dio);
}
