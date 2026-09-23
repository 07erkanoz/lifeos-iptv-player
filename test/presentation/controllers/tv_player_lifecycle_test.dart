import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_config.dart';
import 'package:lifeostv/presentation/screens/player/tv_video_player_screen.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Wakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
}

class _Video extends VideoPlayerPlatform {
  final events = <int, StreamController<VideoEvent>>{};
  final played = <int>[];
  final paused = <int>[];
  final disposed = <int>[];
  bool initializeImmediately = true;
  @override
  Future<void> init() async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    final id = events.length;
    events[id] = StreamController<VideoEvent>();
    if (initializeImmediately) initialize(id);
    return id;
  }

  void initialize(int id) => events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 1),
      size: const Size(1920, 1080),
    ),
  );
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    played.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    paused.add(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Video native;
  late VideoPlayerPlatform original;
  late WakelockPlusPlatformInterface wakelock;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    wakelock = WakelockPlusPlatformInterface.instance;
    native = _Video();
    VideoPlayerPlatform.instance = native;
    WakelockPlusPlatformInterface.instance = _Wakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvPlaybackConfig.channel, (_) async => null);
  });
  tearDown(() async {
    VideoPlayerPlatform.instance = original;
    WakelockPlusPlatformInterface.instance = wakelock;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvPlaybackConfig.channel, null);
    for (final events in native.events.values) {
      await events.close();
    }
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TvVideoPlayerScreen(
            streamUrl: 'https://example.invalid/live/secret/password/1.ts',
            streamId: 1,
            title: 'Test',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('stalled playback exposes retry and creates a fresh controller', (
    tester,
  ) async {
    await mount(tester);
    expect(native.played, contains(0));
    native.events[0]!.add(VideoEvent(eventType: VideoEventType.bufferingStart));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(native.paused, contains(0));
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(native.disposed, contains(0));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(native.played, contains(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding during initialization cannot start playback', (
    tester,
  ) async {
    native.initializeImmediately = false;
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    native.initialize(0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(native.played, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native errors never render credential-bearing messages', (
    tester,
  ) async {
    await mount(tester);
    native.events[0]!.addError(
      PlatformException(
        code: 'codec',
        message: 'https://host/secret/password/file',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('secret'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(native.played, contains(1));
    await tester.pumpWidget(const SizedBox());
  });
}
