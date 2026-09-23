import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:lifeostv/data/services/epg_request_gate.dart';
import 'package:lifeostv/presentation/state/epg_request_provider.dart';
import 'package:lifeostv/presentation/widgets/player/channel_list_overlay.dart';
import 'package:lifeostv/presentation/widgets/player/epg_overlay.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:drift/native.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart'
    show VideoType, PlayerChannel;
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

class _CachedEpgOnly extends EpgRequestGate {
  @override
  Future<void> request(
    int accountId,
    int channelId,
    Future<bool> Function() load,
  ) async {}
}

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
  final sources = <DataSource>[];
  final selectedTracks = <String>[];
  final sought = <Duration>[];
  Duration position = Duration.zero;
  final paused = <int>[];
  final disposed = <int>[];
  bool initializeImmediately = true;
  Duration duration = const Duration(minutes: 1);
  @override
  Future<void> init() async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = events.length;
    events[id] = StreamController<VideoEvent>();
    if (initializeImmediately) initialize(id);
    return id;
  }

  @override
  Future<List<VideoAudioTrack>> getAudioTracks(int playerId) async => [
    const VideoAudioTrack(
      id: 'en',
      label: null,
      isSelected: true,
      language: 'English',
    ),
    const VideoAudioTrack(
      id: 'tr',
      label: null,
      isSelected: false,
      language: 'Turkish',
    ),
  ];
  @override
  Future<void> selectAudioTrack(int playerId, String trackId) async {
    selectedTracks.add(trackId);
  }

  @override
  bool isAudioTrackSupportAvailable() => true;

  void initialize(int id) => events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: duration,
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
  Future<void> seekTo(int playerId, Duration position) async {
    sought.add(position);
    this.position = position;
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
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SharedPreferences prefs;
  late _Video native;
  late VideoPlayerPlatform original;
  late WakelockPlusPlatformInterface wakelock;
  late List<MethodCall> configurations;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    original = VideoPlayerPlatform.instance;
    wakelock = WakelockPlusPlatformInterface.instance;
    native = _Video();
    configurations = [];
    VideoPlayerPlatform.instance = native;
    WakelockPlusPlatformInterface.instance = _Wakelock();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvPlaybackConfig.channel, (call) async {
          configurations.add(call);
          return null;
        });
  });
  tearDown(() async {
    await db.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    VideoPlayerPlatform.instance = original;
    WakelockPlusPlatformInterface.instance = wakelock;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TvPlaybackConfig.channel, null);
    for (final events in native.events.values) {
      await events.close();
    }
  });
  Future<void> mount(WidgetTester tester, {TvVideoPlayerScreen? player}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsProvider.overrideWith(_Settings.new),
          rootDatabaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(db),
          epgRequestGateProvider.overrideWithValue(_CachedEpgOnly()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home:
              player ??
              const TvVideoPlayerScreen(
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

  testWidgets(
    'native subtitle menu can turn subtitles off and restore D-pad focus',
    (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvPlaybackConfig.channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'resolveSubtitlePlayer' => 91,
              'getSubtitleTracks' => [
                {
                  'group': 0,
                  'track': 1,
                  'formatId': 'tr',
                  'language': 'Turkish',
                  'mime': 'text/vtt',
                  'selected': false,
                },
              ],
              _ => null,
            };
          });
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('tv-subtitles')));
      await tester.pumpAndSettle();
      expect(find.text('Turkish'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.last.method, 'selectSubtitleTrack');
      expect(calls.last.arguments, {'playerId': 91, 'off': true});
      expect(find.byType(AndroidView), findsNothing);
      expect(
        FocusManager.instance.primaryFocus,
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('episode-play-pause')),
            )
            .focusNode,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'quality change retains paused VOD position and configures the replacement',
    (tester) async {
      native.duration = const Duration(hours: 1);
      native.position = const Duration(minutes: 12);
      await mount(
        tester,
        player: const TvVideoPlayerScreen(
          streamUrl: 'https://example.invalid/movie.m3u8',
          title: 'Quality',
          streamId: 3,
          type: VideoType.movie,
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(native.played, [0]);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tv-quality')));
      await tester.pumpAndSettle();
      expect(find.text('Medium (720p)'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        (configurations.where((c) => c.method == 'configure').last.arguments
            as Map)['quality'],
        'medium',
      );
      expect(native.sources, hasLength(2));
      expect(native.sought.last, const Duration(minutes: 12));
      expect(native.played, [0]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'live channel panel switches stream and Back closes EPG without leaving player',
    (tester) async {
      await tester.runAsync(() async {
        await db
            .into(db.programs)
            .insert(
              ProgramsCompanion.insert(
                channelId: 2,
                title: 'Second show',
                start: DateTime.now().subtract(const Duration(minutes: 10)),
                stop: DateTime.now().add(const Duration(hours: 1)),
              ),
            );
      });
      await mount(
        tester,
        player: const TvVideoPlayerScreen(
          streamUrl: 'https://example.invalid/1.ts',
          title: 'First',
          currentProgramTitle: 'Old show',
          streamId: 1,
          channels: [
            PlayerChannel(
              streamId: 1,
              name: 'First',
              url: 'https://example.invalid/1.ts',
              categoryId: 'news',
            ),
            PlayerChannel(
              streamId: 2,
              name: 'Second',
              url: 'https://example.invalid/2.ts',
              categoryId: 'news',
              httpHeaders: {'User-Agent': 'SecondProvider'},
            ),
          ],
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChannelListOverlay), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChannelListOverlay), findsNothing);
      expect(native.sources.last.uri, 'https://example.invalid/2.ts');
      expect(native.sources.last.httpHeaders['User-Agent'], 'SecondProvider');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EpgOverlay), findsOneWidget);
      expect(
        tester
            .widget<EpgOverlay>(find.byType(EpgOverlay))
            .programs
            .single
            .title,
        'Second show',
      );
      expect(find.text('Old show'), findsNothing);
      expect(
        tester.widget<EpgOverlay>(find.byType(EpgOverlay)).channelName,
        'Second',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(EpgOverlay), findsNothing);
      expect(find.byType(TvVideoPlayerScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'TV catch-up replays a past programme and returns to the original live URL',
    (tester) async {
      await tester.runAsync(() async {
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                id: const Value(1),
                name: 'Provider',
                type: 'xtream',
                url: 'https://example.invalid/panel',
                username: const Value('user'),
                password: const Value('pass'),
              ),
            );
        final scope = db.forAccount(1);
        await scope
            .into(scope.programs)
            .insert(
              ProgramsCompanion.insert(
                channelId: 1,
                title: 'Replay programme',
                start: DateTime.now().subtract(const Duration(hours: 2)),
                stop: DateTime.now().subtract(const Duration(hours: 1)),
              ),
            );
      });
      await mount(
        tester,
        player: const TvVideoPlayerScreen(
          streamUrl: 'https://example.invalid/original.ts',
          streamId: 1,
          accountId: 1,
          title: 'Channel',
          httpHeaders: {'Referer': 'https://example.invalid'},
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tv-program-guide')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final guide = tester.widget<EpgOverlay>(find.byType(EpgOverlay));
      expect(guide.programs.single.title, 'Replay programme');
      expect(guide.onCatchUp, isNotNull);
      await tester.runAsync(() => guide.onCatchUp!(guide.programs.single));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        native.sources.last.uri,
        contains('/panel/timeshift/user/pass/60/'),
      );
      expect(
        native.sources.last.httpHeaders['Referer'],
        'https://example.invalid',
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);
      expect(find.byKey(const ValueKey('tv-return-live')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-return-live')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(native.sources.last.uri, 'https://example.invalid/original.ts');
      expect(find.byKey(const ValueKey('tv-return-live')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.runAsync(() => guide.onCatchUp!(guide.programs.single));
      await tester.pump();
      native.events[native.events.keys.last]!.addError(
        PlatformException(
          code: 'archive_unavailable',
          message: 'Archive unavailable',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('tv-error-return-live')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(native.sources.last.uri, 'https://example.invalid/original.ts');
      expect(find.byKey(const ValueKey('tv-error-return-live')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('omitted channel index resolves the requested channel identity', (
    tester,
  ) async {
    await mount(
      tester,
      player: const TvVideoPlayerScreen(
        streamUrl: 'https://example.invalid/second.ts',
        streamId: 2,
        title: 'Second',
        channels: [
          PlayerChannel(
            streamId: 1,
            name: 'First',
            url: 'https://example.invalid/first.ts',
          ),
          PlayerChannel(
            streamId: 2,
            name: 'Second',
            url: 'https://example.invalid/second.ts',
          ),
        ],
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final history = await db.select(db.playbackProgress).get();
    expect(history.single.streamId, 2);
    await tester.tap(find.byKey(const ValueKey('tv-channel-list')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final panel = tester.widget<ChannelListOverlay>(
      find.byType(ChannelListOverlay),
    );
    expect(panel.currentChannelIndex, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('native playback receives provider headers and clean URL', (
    tester,
  ) async {
    await mount(
      tester,
      player: const TvVideoPlayerScreen(
        streamUrl: 'https://example.invalid/a.m3u8|Cookie=session%3Dx',
        title: 'Headers',
        streamId: 1,
        httpHeaders: {
          'User-Agent': 'Provider',
          'Referer': 'https://example.invalid',
        },
      ),
    );
    expect(native.sources.single.uri, 'https://example.invalid/a.m3u8');
    expect(native.sources.single.httpHeaders, {
      'User-Agent': 'Provider',
      'Referer': 'https://example.invalid',
      'Cookie': 'session=x',
    });
    expect(native.sources.single.formatHint, VideoFormat.hls);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'movie D-pad reaches audio selection and restores playback focus',
    (tester) async {
      await mount(
        tester,
        player: const TvVideoPlayerScreen(
          streamUrl: 'https://example.invalid/a.mp4',
          title: 'Movie',
          streamId: 2,
          type: VideoType.movie,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('English'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(native.selectedTracks, ['tr']);
      expect(
        FocusManager.instance.primaryFocus,
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('episode-play-pause')),
            )
            .focusNode,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'live streams without duration create history under the current channel',
    (tester) async {
      native.duration = Duration.zero;
      await mount(tester);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      final rows = await db.select(db.playbackProgress).get();
      expect(rows, hasLength(1));
      expect(rows.single.streamId, 1);
      expect(rows.single.type, 'live');
      expect(rows.single.isFinished, false);
      expect(rows.single.position, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'TV episode controls support D-pad and prevent double navigation',
    (tester) async {
      var next = 0;
      await mount(
        tester,
        player: TvVideoPlayerScreen(
          streamUrl: 'https://example.invalid/episode.mkv',
          streamId: 9001,
          title: 'Show',
          type: VideoType.series,
          saveSeriesSummary: false,
          onNextEpisode: () => next++,
          nextEpisodeTitle: 'S1E2',
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(next, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pump();
      expect(next, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

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
    await tester.pump(const Duration(milliseconds: 1));
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
    await tester.pump(const Duration(milliseconds: 1));
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
    await tester.pump(const Duration(milliseconds: 1));
  });
}
