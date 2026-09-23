import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lifeostv/presentation/controllers/player_window_controller.dart';

/// Holds the shared player/controller while PiP mode is active.
class PipData {
  final Player player;
  final VideoController controller;
  final String title;
  final String? logo;
  final String url;
  final String typeName;

  const PipData({
    required this.player,
    required this.controller,
    required this.title,
    this.logo,
    required this.url,
    required this.typeName,
  });
}

/// Whether PiP runs in "shrink the whole window" mode.
///
/// On every desktop platform (Windows + macOS + Linux) we resize the host
/// window down to PiP dimensions and pin it always-on-top, so the user
/// effectively sees ONLY the floating mini player — the rest of the app
/// disappears. Previously Win/macOS used an in-app FloatingPipOverlay,
/// which left the full app window visible behind a small video tile —
/// not what users expect from PiP.
bool get pipUsesWindowMode =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class PipNotifier extends Notifier<PipData?> {
  late PlayerWindowController _window;
  Future<void> _tail = Future.value();
  final _releasedPlayers = Expando<bool>();

  @override
  PipData? build() {
    if (pipUsesWindowMode) _window = ref.read(playerWindowControllerProvider);
    return null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Share the player owned by the mounted route. On desktop, shrink the host
  /// window to a floating mini-player and pin it always-on-top.
  Future<void> enterPip({
    required Player player,
    required VideoController controller,
    required String title,
    String? logo,
    required String url,
    String typeName = 'live',
  }) => _serialize(() async {
    if (state != null || _releasedPlayers[player] == true) return;
    state = PipData(
      player: player,
      controller: controller,
      title: title,
      logo: logo,
      url: url,
      typeName: typeName,
    );
    try {
      if (pipUsesWindowMode) await _window.enterPip();
    } catch (_) {
      state = null;
      rethrow;
    }
  });

  /// The route continues to own the player; restore geometry before revealing it.
  Future<void> closePip() => _serialize(() async {
    if (pipUsesWindowMode) await _window.leavePip();
    state = null;
  });

  Future<PipData?> expandToFullscreen() => _serialize(() async {
    final data = state;
    if (pipUsesWindowMode) await _window.leavePip();
    state = null;
    return data;
  });

  /// Route disposal can occur independently of the overlay's close button.
  Future<void> releasePlayer(Player player) {
    // Invalidate entry synchronously even if its queued callback hasn't run.
    _releasedPlayers[player] = true;
    return _serialize(() async {
      if (!identical(state?.player, player)) return;
      state = null;
      // The route queues endSession immediately; it owns window restoration too.
    });
  }
}

final pipProvider = NotifierProvider<PipNotifier, PipData?>(PipNotifier.new);
