// Run a release build with -t tool/linux_player_smoke.dart, then pass one or
// more LOCAL fixture paths. Uses no accounts, preferences or application DB.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/controllers/playback_session.dart';
import 'package:lifeostv/presentation/controllers/playback_seek_controller.dart';
import 'package:lifeostv/presentation/controllers/player_window_controller.dart';
import 'package:lifeostv/utils/mpv_config.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('LifeOS player smoke');
  await windowManager.setMinimumSize(appWindowMinimumSize);
  await windowManager.setSize(const Size(960, 540));
  runApp(
    MaterialApp(
      home: Scaffold(body: Smoke(fixtures: args)),
    ),
  );
}

class Smoke extends StatefulWidget {
  const Smoke({super.key, required this.fixtures});
  final List<String> fixtures;
  @override
  State<Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<Smoke> {
  VideoController? video;
  String status = 'Starting';
  final results = <Map<String, Object?>>[];
  final windows = PlayerWindowController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  void record(String name, Object? value) {
    final row = {'check': name, 'value': value};
    results.add(row);
    stdout.writeln(jsonEncode(row));
    if (mounted) setState(() => status = name);
  }

  Future<void> until(bool Function() predicate, String name) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('Timeout: $name');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> windowChecks() async {
    await windows.beginSession();
    for (var i = 0; i < 3; i++) {
      await windows.setFullscreen(true);
      if (!await windowManager.isFullScreen()) {
        throw StateError('fullscreen entry');
      }
      await windows.setFullscreen(false);
      if (await windowManager.isFullScreen()) {
        throw StateError('fullscreen exit');
      }
    }
    record('fullscreen 3 round trips', true);
    await windows.toggleAlwaysOnTop();
    record(
      'always on top requested/native',
      await windowManager.isAlwaysOnTop(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await windows.toggleAlwaysOnTop();
    await windows.setFullscreen(true);
    await windows.enterPip();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final size = await windowManager.getSize();
    record('pip size', [size.width, size.height]);
    if (await windowManager.isFullScreen() ||
        size.width > 450 ||
        size.height > 300) {
      throw StateError('PiP did not become a small window');
    }
    await windows.leavePip();
    if (!await windowManager.isFullScreen()) {
      throw StateError('PiP fullscreen restoration');
    }
    await windows.endSession();
    record('pip restored fullscreen then session restored window', true);
  }

  Future<void> play(
    String path,
    bool hardware, {
    bool testWindows = false,
  }) async {
    if (!File(path).existsSync()) throw ArgumentError('Local fixture missing');
    final player = Player(
      configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
    );
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: hardware,
        hwdec: MpvConfig.decoder(hardwareAcceleration: hardware),
      ),
    );
    setState(() => video = controller);
    final native = player.platform as NativePlayer;
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    final session = PlaybackSession(
      initialize: () async {
        await MpvConfig.apply(
          native,
          live: false,
          settings: AppSettings(hardwareAcceleration: hardware),
        );
        await player.setVolume(0);
      },
      openMedia: (url) => player.open(Media(url)),
      disposePlayer: player.dispose,
    );
    final seek = PlaybackSeekController(
      position: () => player.state.position,
      duration: () => player.state.duration,
      seek: player.seek,
      onPreview: (_) {},
      onError: () => errors.add('seek failed'),
    );
    try {
      final watch = Stopwatch()..start();
      await session.open(path);
      await until(
        () =>
            player.state.position.inMilliseconds >= 500 &&
            player.state.width != null,
        'first playback',
      );
      record(
        'startup ${path.split('/').last} hardware=$hardware',
        watch.elapsedMilliseconds,
      );
      final properties = <String, String>{};
      for (final name in [
        'video-codec',
        'hwdec-current',
        'hwdec',
        'video-params/pixelformat',
        'demuxer-max-bytes',
        'cache-secs',
        'avsync',
        'decoder-frame-drop-count',
        'frame-drop-count',
      ]) {
        properties[name] = await native.getProperty(name);
      }
      record('decoder/cache', properties);
      await player.pause();
      await seek.commit(const Duration(seconds: 12));
      await until(
        () => (player.state.position.inSeconds - 12).abs() <= 1,
        'seek forward',
      );
      await seek.commit(const Duration(seconds: 2));
      await until(
        () => (player.state.position.inSeconds - 2).abs() <= 1,
        'seek backward',
      );
      record('seek forward/backward', true);
      await player.play();
      if (testWindows) await windowChecks();
      final settleSeconds =
          int.tryParse(Platform.environment['SMOKE_SETTLE_SECONDS'] ?? '') ?? 3;
      await Future<void>.delayed(Duration(seconds: settleSeconds.clamp(3, 15)));
      final decoder = await native.getProperty('hwdec-current');
      final directHardware =
          decoder != 'no' && decoder.isNotEmpty && !decoder.endsWith('-copy');
      final screenshot = directHardware
          ? null
          : await player.screenshot(format: 'image/png');
      // A zero-copy hardware frame may not support mpv raw readback.
      // Capture the native window separately to verify the displayed image.
      if (screenshot == null) {
        if (!directHardware) throw StateError('No decoded software frame');
        record(
          'raw screenshot',
          'direct hardware frame; inspect native window capture',
        );
      }
      final output =
          '${Platform.environment['SMOKE_OUTPUT'] ?? '/tmp/iptv-player3-smoke'}.${path.split('/').last}.$hardware.png';
      if (screenshot != null) {
        await File(output).writeAsBytes(screenshot);
        record('decoded frame', output);
      }
      record('end A/V', await native.getProperty('avsync'));
      record(
        'end dropped frames',
        await native.getProperty('frame-drop-count'),
      );
      if (errors.isNotEmpty) throw StateError('Player errors: $errors');
    } finally {
      seek.dispose();
      setState(() => video = null);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await session.close();
      await subscription.cancel();
    }
  }

  Future<void> run() async {
    var success = false;
    try {
      if (widget.fixtures.isEmpty) {
        throw ArgumentError('Pass local fixture paths');
      }
      for (final path in widget.fixtures) {
        await play(path, true, testWindows: path == widget.fixtures.first);
        await play(path, false);
      }
      success = true;
    } catch (error, stack) {
      record('failure', '$error\n$stack');
    } finally {
      try {
        await windows.endSession();
      } catch (_) {}
      windows.dispose();
      record('passed', success);
      await File(
        '${Platform.environment['SMOKE_OUTPUT'] ?? '/tmp/iptv-player3-smoke'}.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
      exit(success ? 0 : 1);
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(
      children: [
        if (video case final controller?)
          Positioned.fill(
            child: Video(controller: controller, controls: NoVideoControls),
          ),
        Positioned(
          left: 16,
          top: 16,
          child: Text(
            status,
            style: const TextStyle(
              color: Colors.white,
              backgroundColor: Colors.black,
            ),
          ),
        ),
      ],
    ),
  );
}
