import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/core/media_resource_registry.dart';
import 'package:lifeostv/core/playback_signal.dart';

class DesktopMediaShutdown with WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    playbackActiveNotifier.value = true;
    unawaited(_closeAfterMedia());
  }

  Future<void> _closeAfterMedia() async {
    try {
      await mediaResourceRegistry.closeAll();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (_) {
      _closing = false;
      debugPrint(
        '[playback] Native media cleanup failed; keeping engine alive.',
      );
    }
  }
}
