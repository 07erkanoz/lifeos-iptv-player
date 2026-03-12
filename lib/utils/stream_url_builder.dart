import 'package:lifeostv/domain/models/app_settings.dart';

/// Centralized stream URL builder for all screen types.
/// Uses HLS (.m3u8) for adaptive bitrate when quality is set to auto.
class StreamUrlBuilder {
  const StreamUrlBuilder._();

  /// Build a live TV stream URL.
  /// When [quality] is auto, uses .m3u8 (HLS) for adaptive bitrate.
  /// Otherwise uses .ts (MPEG-TS) for fixed quality.
  static String live(
    String baseUrl,
    String username,
    String password,
    int streamId, {
    StreamQuality quality = StreamQuality.auto,
  }) {
    final ext = quality == StreamQuality.auto ? 'm3u8' : 'ts';
    return '$baseUrl/live/$username/$password/$streamId.$ext';
  }

  /// Build a VOD (movie) stream URL. VOD always uses the same format.
  static String movie(
    String baseUrl,
    String username,
    String password,
    int streamId,
  ) {
    return '$baseUrl/movie/$username/$password/$streamId.mkv';
  }

  /// Build a series episode stream URL. Always uses the same format.
  static String series(
    String baseUrl,
    String username,
    String password,
    int streamId,
  ) {
    return '$baseUrl/series/$username/$password/$streamId.mkv';
  }

  /// Generic builder based on content type.
  /// If [directUrl] is provided (M3U accounts), returns it directly.
  static String build(
    String baseUrl,
    String username,
    String password,
    int streamId,
    String type, {
    StreamQuality quality = StreamQuality.auto,
    String? directUrl,
  }) {
    // M3U accounts store the stream URL directly
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    switch (type) {
      case 'live':
        return live(baseUrl, username, password, streamId, quality: quality);
      case 'movie':
        return movie(baseUrl, username, password, streamId);
      case 'series':
        return series(baseUrl, username, password, streamId);
      default:
        return '$baseUrl/$username/$password/$streamId';
    }
  }
}
