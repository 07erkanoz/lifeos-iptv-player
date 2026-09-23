import 'package:lifeostv/domain/models/app_settings.dart';

/// Centralized stream URL builder for all screen types.
/// HLS may be adaptive when the provider supplies a master playlist.
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
    return _path(baseUrl, ['live', username, password, '$streamId.$ext']);
  }

  /// Prefer the provider URL or container; MKV is a legacy fallback only.
  static String movie(
    String baseUrl,
    String username,
    String password,
    int streamId, {
    String? extension,
    String? directUrl,
  }) {
    if (directUrl != null && directUrl.trim().isNotEmpty) {
      return directUrl.trim();
    }
    return _path(baseUrl, [
      'movie',
      username,
      password,
      '$streamId.${_extension(extension, 'mkv')}',
    ]);
  }

  /// Build an episode URL using its provider-supplied container or direct URL.
  static String series(
    String baseUrl,
    String username,
    String password,
    int streamId, {
    String? extension,
    String? directUrl,
  }) {
    if (directUrl != null && directUrl.trim().isNotEmpty) {
      return directUrl.trim();
    }
    return _path(baseUrl, [
      'series',
      username,
      password,
      '$streamId.${_extension(extension, 'mkv')}',
    ]);
  }

  /// Build an Xtream timeshift / catch-up URL.
  ///
  /// Pattern: `base/timeshift/user/pass/duration_minutes/start/stream_id.ts`.
  /// The start timestamp uses the `yyyy-MM-dd:HH-mm` format.
  ///
  /// Use this to replay a programme that started at [start] and ran
  /// for [duration]. The Xtream server keeps a rolling timeshift
  /// buffer — typically the last 1-7 days, depending on the
  /// provider. URLs older than that range silently 404; callers
  /// should gate the catch-up button on `start` being within a
  /// reasonable window.
  ///
  /// The format component is `.ts` rather than `.m3u8` because
  /// timeshift sessions are server-cut MPEG-TS files; HLS variant
  /// playlists don't apply to a finite past window.
  static String timeshift(
    String baseUrl,
    String username,
    String password,
    int streamId, {
    required DateTime start,
    required Duration duration,
  }) {
    // Server expects local-server-time format. Most Xtream panels
    // are TR / UTC+3; we send the user's local clock here and let
    // the server interpret. If a provider needs UTC, we'd swap to
    // start.toUtc() — leave the surface flexible.
    final s = start;
    final stamp =
        '${s.year}-${_pad2(s.month)}-${_pad2(s.day)}:${_pad2(s.hour)}-${_pad2(s.minute)}';
    final mins = duration.inMinutes.clamp(1, 24 * 60);
    return _path(baseUrl, [
      'timeshift',
      username,
      password,
      '$mins',
      stamp,
      '$streamId.ts',
    ]);
  }

  static String _path(String baseUrl, List<String> segments) {
    final base = Uri.parse(baseUrl.trim());
    final prefix = base.pathSegments.toList();
    while (prefix.isNotEmpty && prefix.last.isEmpty) {
      prefix.removeLast();
    }
    return Uri(
      scheme: base.scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [...prefix, ...segments],
    ).toString();
  }

  static String _extension(String? value, String fallback) {
    final ext = (value ?? '')
        .trim()
        .replaceFirst(RegExp(r'^\.'), '')
        .toLowerCase();
    return RegExp(r'^[a-z0-9]+$').hasMatch(ext) ? ext : fallback;
  }

  /// Returns null when a provider has supplied neither a direct source nor a
  /// container, so legacy catalogues can request VOD details before guessing.
  static String? vodFromMetadata(
    String baseUrl,
    String username,
    String password,
    int streamId,
    Map metadata,
  ) {
    final direct = metadata['direct_source']?.toString().trim();
    final extension = metadata['container_extension']?.toString().trim();
    if ((direct == null || direct.isEmpty) &&
        (extension == null || extension.isEmpty)) {
      return null;
    }
    return movie(
      baseUrl,
      username,
      password,
      streamId,
      extension: extension,
      directUrl: direct,
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

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
    String? extension,
  }) {
    // M3U accounts store the stream URL directly
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    switch (type) {
      case 'live':
        return live(baseUrl, username, password, streamId, quality: quality);
      case 'movie':
        return movie(
          baseUrl,
          username,
          password,
          streamId,
          extension: extension,
        );
      case 'series':
        return series(
          baseUrl,
          username,
          password,
          streamId,
          extension: extension,
        );
      default:
        return _path(baseUrl, [username, password, '$streamId']);
    }
  }
}
