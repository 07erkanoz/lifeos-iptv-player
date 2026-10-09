// Local fixtures only; no application database, account or provider access.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/core/desktop_media_shutdown.dart';
import 'package:lifeostv/core/managed_player.dart';
import 'package:lifeostv/core/media_resource_registry.dart';
import 'package:lifeostv/core/playback_signal.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/utils/mpv_config.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Supply one local fixture path');
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.setTitle('LifeOS audio/lifecycle fixture test');
  windowManager.addListener(DesktopMediaShutdown());
  await windowManager.show();
  runApp(MaterialApp(home: Harness(path: args.single)));
}

class Harness extends StatefulWidget {
  const Harness({super.key, required this.path});
  final String path;
  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  late final players = [
    ManagedPlayer(),
    ManagedPlayer(preview: true),
    ManagedPlayer(preview: true),
  ];
  late final controllers = [
    for (final player in players) VideoController(player),
  ];
  final result = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    final output = File(
      Platform.environment['SMOKE_OUTPUT'] ??
          '/tmp/lifeos-audio-lifecycle.json',
    );
    try {
      for (var i = 0; i < players.length; i++) {
        await players[i].setVolume(0);
        await MpvConfig.apply(
          players[i].platform as NativePlayer,
          live: false,
          settings: const AppSettings(),
        );
        await players[i].open(Media(widget.path));
      }
      result['previewAudioIds'] = [
        for (final p in players.skip(1))
          await (p.platform as NativePlayer).getProperty('aid'),
      ];
      if ((result['previewAudioIds'] as List).any((id) => id != 'no')) {
        throw StateError('Muted preview decoded audio');
      }
      playbackActiveNotifier.value = true;
      await Future<void>.delayed(const Duration(seconds: 1));
      result['previewsPaused'] = players.skip(1).every((p) => !p.state.playing);
      if (result['previewsPaused'] != true)
        throw StateError('Preview still plays');
      final before = players.first.state.position;
      await Future<void>.delayed(const Duration(seconds: 6));
      result['advanceMs'] =
          (players.first.state.position - before).inMilliseconds;
      if ((result['advanceMs'] as int) < 4000)
        throw StateError('Playback stalled');
      result['audioSampleRate'] = await (players.first.platform as NativePlayer)
          .getProperty('audio-params/samplerate');
      if (int.tryParse('${result['audioSampleRate']}') == null) {
        throw StateError('Foreground audio not initialized');
      }
      await players.first.pause();
      await players.first.seek(const Duration(seconds: 2));
      await players.first.play();
      await Future<void>.delayed(const Duration(seconds: 2));
      await players.first.open(Media(widget.path));
      await Future<void>.delayed(const Duration(seconds: 2));
      result['reopenPlaying'] = players.first.state.playing;
      await mediaResourceRegistry.closeAll();
      result['playersDisposed'] = players.every(
        (p) => (p.platform as NativePlayer).disposed,
      );
      if (result['playersDisposed'] != true)
        throw StateError('Native player live');
      result['passed'] = true;
    } catch (error) {
      result['passed'] = false;
      result['error'] = '$error';
    }
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
    // Exercise real GTK/Flutter engine shutdown, rather than Process.exit().
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        for (final controller in controllers)
          Expanded(
            child: Video(controller: controller, controls: NoVideoControls),
          ),
      ],
    ),
  );
}
