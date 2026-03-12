import 'package:dio/dio.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/data/services/api_queue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'xtream_api_service.g.dart';

class XtreamApiService {
  final Dio _dio;
  final ApiCache _cache = ApiCache.instance;
  final ApiQueue _queue = ApiQueue.instance;

  XtreamApiService(this._dio);

  /// Normalize URL: extract base server URL from various formats
  /// Handles: http://host:port, http://host:port/player_api.php?...,
  /// http://host:port/get.php?..., full m3u links, etc.
  static String normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http')) {
      u = 'http://$u';
    }
    // Remove trailing slashes
    u = u.replaceAll(RegExp(r'/+$'), '');

    // If URL contains player_api.php or get.php, extract base URL
    final apiIdx = u.indexOf('/player_api.php');
    if (apiIdx > 0) {
      u = u.substring(0, apiIdx);
    }
    final getIdx = u.indexOf('/get.php');
    if (getIdx > 0) {
      u = u.substring(0, getIdx);
    }
    // Remove any path after port (e.g., /live/user/pass/...)
    try {
      final uri = Uri.parse(u);
      // Rebuild with just scheme, host, port
      if (uri.host.isNotEmpty) {
        final port = uri.hasPort ? ':${uri.port}' : '';
        u = '${uri.scheme}://${uri.host}$port';
      }
    } catch (_) {}

    return u;
  }

  Future<Map<String, dynamic>> authenticate(String url, String username, String password) async {
    final fullUrl = normalizeUrl(url);

    try {
      final response = await _dio.get(
        '$fullUrl/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
        },
        options: Options(responseType: ResponseType.json),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['user_info'] != null) {
          if (data['user_info']['auth'] == 1) {
            return data;
          }
          throw Exception('Invalid credentials: authentication denied by server');
        }
        throw Exception('Invalid server response: missing user_info');
      }
      throw Exception('Server returned status ${response.statusCode}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('Connection timeout: server at $fullUrl is not responding');
      } else if (e.type == DioExceptionType.connectionError) {
        throw Exception('Cannot connect to server: $fullUrl - check URL and port');
      } else if (e.response?.statusCode == 403) {
        throw Exception('Access denied (403): server blocked the request');
      } else if (e.response?.statusCode == 404) {
        throw Exception('Server not found (404): $fullUrl may not be an Xtream server');
      }
      throw Exception('Connection error: ${e.message}');
    }
  }

  Future<List<dynamic>> getCategories(String url, String username, String password, String action) async {
    final cacheKey = 'cat_${action}_$username';
    final cached = _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _queue.enqueue<List<dynamic>>(
      cacheKey,
      () async {
        final response = await _dio.get(
          '$url/player_api.php',
          queryParameters: {'username': username, 'password': password, 'action': action},
        );
        if (response.data is List) return response.data as List<dynamic>;
        return <dynamic>[];
      },
      priority: ApiPriority.normal,
    );
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.categoriesTtl);
    }
    return result;
  }

  Future<List<dynamic>> getStreams(String url, String username, String password, String action, {String? categoryId}) async {
    final cacheKey = 'streams_${action}_${categoryId ?? 'all'}_$username';
    final cached = _cache.get<List<dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _queue.enqueue<List<dynamic>>(
      cacheKey,
      () async {
        final Map<String, dynamic> query = {
          'username': username,
          'password': password,
          'action': action,
        };
        if (categoryId != null) query['category_id'] = categoryId;

        final response = await _dio.get('$url/player_api.php', queryParameters: query);
        if (response.data is List) return response.data as List<dynamic>;
        return <dynamic>[];
      },
      priority: ApiPriority.normal,
    );
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.streamsTtl);
    }
    return result;
  }

  /// Get VOD (movie) detail info: plot, cast, genre, director, duration, backdrop
  /// Uses cache (30 min TTL) + queue (max 1 concurrent request)
  Future<Map<String, dynamic>?> getVODInfo(String url, String username, String password, int vodId) async {
    final cacheKey = 'vod_info_$vodId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _queue.enqueue<Map<String, dynamic>?>(
        cacheKey,
        () async {
          final response = await _dio.get(
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
        },
        priority: ApiPriority.high,
      );
      if (result != null) {
        _cache.set(cacheKey, result, ApiCache.vodInfoTtl);
      }
      return result;
    } catch (_) {}
    return null;
  }

  /// Get Series info: seasons, episodes with details
  /// Uses cache (30 min TTL) + queue (max 1 concurrent request)
  Future<Map<String, dynamic>?> getSeriesInfo(String url, String username, String password, int seriesId) async {
    final cacheKey = 'series_info_$seriesId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    try {
      final result = await _queue.enqueue<Map<String, dynamic>?>(
        cacheKey,
        () async {
          final response = await _dio.get(
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
        },
        priority: ApiPriority.high,
      );
      if (result != null) {
        _cache.set(cacheKey, result, ApiCache.seriesInfoTtl);
      }
      return result;
    } catch (_) {}
    return null;
  }

  /// Get short EPG for a single stream (default 20 listings)
  /// Uses cache (15 min TTL) + queue
  Future<Map<String, dynamic>> getEpg(String url, String username, String password, String streamId, {int? limit}) async {
    final cacheKey = 'epg_$streamId';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _queue.enqueue<Map<String, dynamic>>(
      cacheKey,
      () async {
        final response = await _dio.get(
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
      },
      priority: ApiPriority.normal,
    );
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.epgTtl);
    }
    return result;
  }

  /// Get full EPG table for all streams (or a single stream)
  /// Uses cache (15 min TTL) + queue
  Future<Map<String, dynamic>> getAllEpg(String url, String username, String password, {String? streamId}) async {
    final cacheKey = streamId != null ? 'all_epg_$streamId' : 'all_epg';
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final result = await _queue.enqueue<Map<String, dynamic>>(
      cacheKey,
      () async {
        final Map<String, dynamic> query = {
          'username': username,
          'password': password,
          'action': 'get_simple_data_table',
        };
        if (streamId != null) query['stream_id'] = streamId;

        final response = await _dio.get(
          '$url/player_api.php',
          queryParameters: query,
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        if (response.data is Map) return response.data as Map<String, dynamic>;
        return <String, dynamic>{};
      },
      priority: ApiPriority.normal,
    );
    if (result.isNotEmpty) {
      _cache.set(cacheKey, result, ApiCache.epgAllTtl);
    }
    return result;
  }
}

@riverpod
XtreamApiService xtreamApiService(Ref ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
    headers: {'User-Agent': 'LifeOsTV/1.0'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onError: (error, handler) async {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        try {
          final response = await dio.fetch(error.requestOptions);
          return handler.resolve(response);
        } catch (_) {
          return handler.next(error);
        }
      }
      return handler.next(error);
    },
  ));

  return XtreamApiService(dio);
}
