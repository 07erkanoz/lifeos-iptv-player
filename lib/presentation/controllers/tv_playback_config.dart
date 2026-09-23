import 'package:flutter/services.dart';
import 'package:lifeostv/domain/models/app_settings.dart';

/// Configures the next ExoPlayer instance in the engine-local Android plugin.
class TvPlaybackConfig {
  static const channel = MethodChannel('com.lifeostv.lifeostv/playback_config');

  static Future<void> apply(AppSettings settings, {required bool live}) =>
      channel.invokeMethod<void>('configure', {
        'hardwareAcceleration': settings.hardwareAcceleration,
        'bufferSeconds': settings.bufferDuration.clamp(5, 120),
        'live': live,
        'quality': settings.streamQuality.name,
      });
}
