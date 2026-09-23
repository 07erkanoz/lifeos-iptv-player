import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(TvPlaybackConfig.channel, null),
  );

  test(
    'TV preferences reach the native decoder before player creation',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(TvPlaybackConfig.channel, (
        call,
      ) async {
        received = call;
        return null;
      });
      await TvPlaybackConfig.apply(
        const AppSettings(
          hardwareAcceleration: false,
          bufferDuration: 999,
          streamQuality: StreamQuality.medium,
        ),
        live: true,
      );
      expect(received?.method, 'configure');
      expect(received?.arguments, {
        'hardwareAcceleration': false,
        'bufferSeconds': 120,
        'live': true,
        'quality': 'medium',
      });
    },
  );
  test(
    'missing native bridge surfaces an error instead of ignoring preferences',
    () async {
      await expectLater(
        TvPlaybackConfig.apply(const AppSettings(), live: false),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );
}
