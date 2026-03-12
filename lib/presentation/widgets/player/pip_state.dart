import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Holds the shared player/controller when PiP mode is active
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

/// Single unified PiP mode for all desktop platforms:
/// in-app floating mini player (no native window resize mode).
bool get pipUsesWindowMode => false;

class PipNotifier extends Notifier<PipData?> {
  @override
  PipData? build() => null;

  /// Enter PiP – transfers ownership of the player from full-screen player.
  /// Uses floating overlay mode on desktop and native PiP on Android.
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
  }

  /// Close PiP – disposes player, clears state, restores window (Linux)
  Future<void> closePip() async {
    state?.player.dispose();
    state = null;
  }

  /// Expand PiP back to full-screen – returns data without disposing player, restores window (Linux)
  Future<PipData?> expandToFullscreen() async {
    return state;
  }

  /// Detaches the in-app PiP overlay without disposing the shared player.
  void detachPip() {
    state = null;
  }
}

final pipProvider = NotifierProvider<PipNotifier, PipData?>(PipNotifier.new);
