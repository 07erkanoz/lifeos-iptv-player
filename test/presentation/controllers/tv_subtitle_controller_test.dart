import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/tv_subtitle_controller.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(TvPlaybackConfig.channel, null),
  );
  test(
    'subtitle controls preserve native session and manifest identity',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(TvPlaybackConfig.channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'resolveSubtitlePlayer' => 73,
          'getSubtitleTracks' => [
            {
              'group': 2,
              'track': 0,
              'formatId': 'tr',
              'language': 'tr',
              'mime': 'text/vtt',
              'selected': false,
            },
          ],
          _ => null,
        };
      });
      final controller = (await TvSubtitleController.resolve(
        'https://example.invalid/one',
      ))!;
      final tracks = await controller.tracks();
      await controller.select(tracks.single);
      expect((calls.last.arguments as Map)['playerId'], 73);
      expect((calls.last.arguments as Map)['formatId'], 'tr');
      await controller.select(null);
      expect(calls.last.arguments, {'playerId': 73, 'off': true});
    },
  );
  test(
    'missing or ambiguous native session never yields a usable controller',
    () async {
      messenger.setMockMethodCallHandler(
        TvPlaybackConfig.channel,
        (_) async => null,
      );
      expect(
        await TvSubtitleController.resolve('https://example.invalid/gone'),
        isNull,
      );
      messenger.setMockMethodCallHandler(
        TvPlaybackConfig.channel,
        (_) async => throw PlatformException(code: 'subtitle_session'),
      );
      await expectLater(
        TvSubtitleController.resolve('https://example.invalid/duplicate'),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
