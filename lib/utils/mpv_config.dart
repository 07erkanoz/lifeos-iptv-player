import 'package:flutter/foundation.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:media_kit/media_kit.dart';

/// Conservative decoder/cache policy. GPU vendor names do not prove decoder
/// availability or texture interop; let mpv probe supported devices at runtime.
class MpvConfig {
  const MpvConfig._();

  static String decoder({
    required bool hardwareAcceleration,
    TargetPlatform? platform,
  }) {
    if (!hardwareAcceleration) return 'no';
    return (platform ?? defaultTargetPlatform) == TargetPlatform.android
        ? 'mediacodec-copy'
        : 'auto-safe';
  }

  static Map<String, String> options({
    required bool live,
    required AppSettings settings,
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final mobile =
        target == TargetPlatform.android || target == TargetPlatform.iOS;
    final seconds = settings.bufferDuration.clamp(5, live ? 30 : 120);
    return {
      'hwdec': decoder(
        hardwareAcceleration: settings.hardwareAcceleration,
        platform: target,
      ),
      // Keep mpv's codec whitelist and fallback policy; don't force every codec
      // through hardware or apply the global low-latency profile to VOD.
      'video-sync': 'audio',
      'interpolation': 'no',
      'framedrop': 'vo',
      'cache': 'yes',
      'cache-secs': '$seconds',
      'demuxer-readahead-secs': '$seconds',
      'demuxer-max-bytes': live
          ? '32MiB'
          : mobile
          ? '64MiB'
          : '128MiB',
      'demuxer-max-back-bytes': live
          ? '4MiB'
          : mobile
          ? '16MiB'
          : '32MiB',
      'cache-pause': 'yes',
      'cache-pause-initial': 'yes',
      'cache-pause-wait': live ? '1' : '2',
      if (settings.lastPlayerSubtitleLanguage == null) 'sid': 'no',
      'hls-bitrate': switch (settings.streamQuality) {
        StreamQuality.auto => 'max',
        StreamQuality.high => 'max',
        StreamQuality.medium => '3000000',
        StreamQuality.low => '1000000',
      },
    };
  }

  static Future<void> apply(
    NativePlayer player, {
    required bool live,
    required AppSettings settings,
    bool Function()? cancelled,
  }) async {
    for (final entry in options(live: live, settings: settings).entries) {
      if (cancelled?.call() == true) return;
      await player.setProperty(entry.key, entry.value);
    }
  }
}
