import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/utils/mpv_config.dart';

void main() {
  test('software setting disables decoding on every platform', () {
    for (final platform in TargetPlatform.values) {
      expect(
        MpvConfig.decoder(hardwareAcceleration: false, platform: platform),
        'no',
      );
    }
  });
  test(
    'desktop decoder probes capabilities rather than forcing a GPU vendor',
    () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      ]) {
        expect(
          MpvConfig.decoder(hardwareAcceleration: true, platform: platform),
          'auto-safe',
        );
      }
      expect(
        MpvConfig.decoder(
          hardwareAcceleration: true,
          platform: TargetPlatform.android,
        ),
        'mediacodec-copy',
      );
    },
  );
  test('live cache stays bounded independently of VOD preference', () {
    final live = MpvConfig.options(
      live: true,
      settings: const AppSettings(bufferDuration: 120),
      platform: TargetPlatform.linux,
    );
    final vod = MpvConfig.options(
      live: false,
      settings: const AppSettings(bufferDuration: 120),
      platform: TargetPlatform.linux,
    );
    expect(live['cache-secs'], '30');
    expect(vod['cache-secs'], '120');
    expect(live['demuxer-max-bytes'], '32MiB');
    expect(vod['demuxer-max-bytes'], '128MiB');
    expect(vod, isNot(contains('profile')));
    expect(vod, isNot(contains('hwdec-codecs')));
  });
  test('invalid cache settings clamp and mobile memory stays bounded', () {
    final options = MpvConfig.options(
      live: false,
      settings: const AppSettings(bufferDuration: -1),
      platform: TargetPlatform.android,
    );
    expect(options['cache-secs'], '5');
    expect(options['demuxer-max-bytes'], '64MiB');
    expect(options['demuxer-max-back-bytes'], '16MiB');
  });
  test('HLS variants respect quality preference without transcoding', () {
    expect(
      MpvConfig.options(
        live: true,
        settings: const AppSettings(streamQuality: StreamQuality.low),
      )['hls-bitrate'],
      '1000000',
    );
    expect(
      MpvConfig.options(
        live: true,
        settings: const AppSettings(streamQuality: StreamQuality.medium),
      )['hls-bitrate'],
      '3000000',
    );
  });
}
