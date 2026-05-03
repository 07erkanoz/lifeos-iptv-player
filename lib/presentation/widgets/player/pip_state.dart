import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

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
  // Restored when PiP is dismissed so the user lands back in the same
  // window geometry they had before they entered the mini player.
  Size? _savedSize;
  Offset? _savedPosition;

  static const double _pipWidth = 380;
  static const double _pipHeight = 230; // 16:9 + small title bar
  static const double _screenMargin = 24;

  @override
  PipData? build() => null;

  /// Enter PiP — transfers ownership of the player from the full-screen
  /// player. On desktop platforms this also shrinks the host window down
  /// to a floating mini-player and pins it always-on-top.
  Future<void> enterPip({
    required Player player,
    required VideoController controller,
    required String title,
    String? logo,
    required String url,
    String typeName = 'live',
  }) async {
    state = PipData(
      player: player,
      controller: controller,
      title: title,
      logo: logo,
      url: url,
      typeName: typeName,
    );

    if (pipUsesWindowMode) {
      await _shrinkWindowToPip();
    }
  }

  /// Close PiP — clears state and restores the host window. The player
  /// itself is owned by the /player screen mounted underneath; whoever
  /// calls closePip() should also pop that route so the player screen's
  /// dispose() can stop & dispose the Player.
  Future<void> closePip() async {
    state = null;
    if (pipUsesWindowMode) {
      await _restoreWindow();
    }
  }

  /// Expand PiP back to fullscreen — just clears state and restores
  /// window size. The /player screen is still mounted under PipOverlay
  /// (main.dart Stacks the overlay over the router), so as soon as
  /// state goes null its build() re-renders the local Video widget
  /// and the user is back to fullscreen.
  Future<PipData?> expandToFullscreen() async {
    final data = state;
    state = null;
    if (pipUsesWindowMode) {
      await _restoreWindow();
    }
    return data;
  }

  /// Clears PiP state without restoring the window. Currently unused —
  /// kept for backwards compatibility while older code paths are still
  /// being migrated. New code should call expandToFullscreen() or
  /// closePip() depending on intent.
  void detachPip() {
    state = null;
  }

  // ─── Window-mode helpers ───────────────────────────────────────────

  Future<void> _shrinkWindowToPip() async {
    try {
      // Capture current geometry so closePip / expand can put it back.
      _savedSize = await windowManager.getSize();
      _savedPosition = await windowManager.getPosition();

      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(_pipWidth, _pipHeight));

      // Re-park the window in the bottom-right of the primary display
      // (where users expect a PiP). We compute from the saved position
      // and saved size to land on the same monitor the app was on.
      final origin = _savedPosition ?? Offset.zero;
      final originalSize = _savedSize ?? const Size(1280, 720);
      final dx = origin.dx + originalSize.width - _pipWidth - _screenMargin;
      final dy = origin.dy + originalSize.height - _pipHeight - _screenMargin;
      await windowManager.setPosition(Offset(
        dx < origin.dx ? origin.dx : dx,
        dy < origin.dy ? origin.dy : dy,
      ));
    } catch (_) {
      // Window manager calls can fail on some Linux WMs (no AOT support,
      // tiling WM, etc.) — swallow and let PiP fall back to the in-app
      // overlay rendered by main.dart.
    }
  }

  Future<void> _restoreWindow() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      if (_savedSize != null) {
        await windowManager.setSize(_savedSize!);
      }
      if (_savedPosition != null) {
        await windowManager.setPosition(_savedPosition!);
      }
    } catch (_) {}
    _savedSize = null;
    _savedPosition = null;
  }
}

final pipProvider = NotifierProvider<PipNotifier, PipData?>(PipNotifier.new);
