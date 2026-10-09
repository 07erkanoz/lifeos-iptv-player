import 'dart:async';
import 'package:media_kit/media_kit.dart';
import 'package:lifeostv/core/media_resource_registry.dart';
import 'package:lifeostv/core/playback_signal.dart';

/// Muted previews neither decode audio nor compete with foreground playback.
/// Desktop shutdown waits for every player to detach its native callbacks.
class ManagedPlayer extends Player {
  factory ManagedPlayer({
    PlayerConfiguration configuration = const PlayerConfiguration(),
    bool preview = false,
  }) {
    if (mediaResourceRegistry.isClosing) {
      throw StateError('Media shutdown is in progress');
    }
    return ManagedPlayer._(configuration, preview);
  }

  ManagedPlayer._(PlayerConfiguration configuration, this.preview)
    : super(configuration: configuration) {
    mediaResourceRegistry.register(this, dispose);
    if (preview) playbackActiveNotifier.addListener(_onForegroundPlayback);
  }

  final bool preview;
  bool _wantsPlayback = false;
  Future<void>? _disposal;
  Future<void>? _previewAudio;

  void _onForegroundPlayback() {
    if (_disposal != null) return;
    final action = playbackActiveNotifier.value
        ? super.pause()
        : _wantsPlayback
        ? super.play()
        : Future<void>.value();
    unawaited(action.catchError((Object _) {}));
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (preview) {
      _wantsPlayback = play;
      await (_previewAudio ??= super.setAudioTrack(AudioTrack.no()));
    }
    if (_disposal != null) return;
    await super.open(
      playable,
      play: play && !(preview && playbackActiveNotifier.value),
    );
  }

  @override
  Future<void> dispose() {
    if (preview) playbackActiveNotifier.removeListener(_onForegroundPlayback);
    return _disposal ??= _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    try {
      await super.dispose();
    } finally {
      mediaResourceRegistry.unregister(this);
    }
  }
}
