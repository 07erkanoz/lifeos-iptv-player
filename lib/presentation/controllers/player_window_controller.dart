import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const appWindowMinimumSize = Size(900, 500);

/// Serializes native window transitions, which can finish after the platform
/// method returns (particularly macOS fullscreen animations).
class PlayerWindowController extends ChangeNotifier with WindowListener {
  PlayerWindowController({bool? waitForFullscreenEvent})
    : _waitForFullscreenEvent = waitForFullscreenEvent ?? Platform.isMacOS {
    windowManager.addListener(this);
  }

  final bool _waitForFullscreenEvent;
  Completer<void>? _fullscreenCompletion;
  bool? _fullscreenTarget;

  bool fullscreen = false;
  bool alwaysOnTop = false;
  bool transitioning = false;
  bool _disposed = false;
  bool? _initialFullscreen;
  bool? _initialAlwaysOnTop;
  _PipWindowSnapshot? _pip;
  Future<void> _tail = Future.value();

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) async {
      transitioning = true;
      _notify();
      try {
        await action();
      } finally {
        try {
          await refresh();
        } finally {
          transitioning = false;
          _notify();
        }
      }
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> beginSession() => _enqueue(() async {
    _initialFullscreen = await windowManager.isFullScreen();
    _initialAlwaysOnTop = await windowManager.isAlwaysOnTop();
  });

  Future<void> refresh() async {
    final fs = await windowManager.isFullScreen();
    final pinned = await windowManager.isAlwaysOnTop();
    fullscreen = fs;
    alwaysOnTop = pinned;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _waitFor(bool expected, Future<bool> Function() read) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (await read() != expected) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Window transition was not acknowledged');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  Future<void> _fullscreen(bool enabled) async {
    if (await windowManager.isFullScreen() == enabled) return;
    // AppKit may update styleMask before its fullscreen animation finishes.
    // Wait for windowDidEnter/ExitFullScreen before another native transition.
    final completion = _waitForFullscreenEvent ? Completer<void>() : null;
    _fullscreenCompletion = completion;
    _fullscreenTarget = enabled;
    try {
      await windowManager.setFullScreen(enabled);
      if (completion != null) {
        await completion.future.timeout(const Duration(seconds: 3));
      }
      await _waitFor(enabled, windowManager.isFullScreen);
    } finally {
      _fullscreenCompletion = null;
      _fullscreenTarget = null;
    }
  }

  Future<void> setFullscreen(bool enabled) => _enqueue(() async {
    if (_pip == null) await _fullscreen(enabled);
  });

  Future<void> toggleFullscreen() => _enqueue(() async {
    if (_pip == null) {
      await _fullscreen(!await windowManager.isFullScreen());
    }
  });

  Future<void> toggleAlwaysOnTop() => _enqueue(() async {
    if (_pip != null) return;
    await windowManager.setAlwaysOnTop(!await windowManager.isAlwaysOnTop());
  });

  Future<void> enterPip() => _enqueue(() async {
    if (_pip != null) return;
    final snapshot = _PipWindowSnapshot(
      fullscreen: await windowManager.isFullScreen(),
      maximized: await windowManager.isMaximized(),
      alwaysOnTop: await windowManager.isAlwaysOnTop(),
      bounds: await windowManager.getBounds(),
    );
    _pip = snapshot;
    try {
      await _fullscreen(false);
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
        await _waitFor(false, windowManager.isMaximized);
      }
      // Capture normal bounds after leaving fullscreen/maximized mode.
      snapshot.bounds = await windowManager.getBounds();
      const size = Size(380, 230);
      await windowManager.setMinimumSize(size);
      await windowManager.setSize(size);
      try {
        final position = await calcWindowPosition(size, Alignment.bottomRight);
        await windowManager.setPosition(position - const Offset(24, 24));
      } catch (_) {
        // Display enumeration isn't supported by every compositor. Keeping
        // the existing origin is safer than inventing off-screen coordinates.
        await windowManager.setPosition(snapshot.bounds.topLeft);
      }
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {
      await _restorePip();
      rethrow;
    }
  });

  Future<void> leavePip() => _enqueue(_restorePip);

  Future<void> _restorePip() async {
    final snapshot = _pip;
    if (snapshot == null) return;
    // Attempt every restoration even if one capability is unsupported.
    Object? failure;
    Future<void> restore(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failure ??= error;
      }
    }

    await restore(() => _fullscreen(false));
    await restore(() => windowManager.setMinimumSize(appWindowMinimumSize));
    await restore(() => windowManager.setBounds(snapshot.bounds));
    await restore(() => windowManager.setAlwaysOnTop(snapshot.alwaysOnTop));
    if (snapshot.maximized) {
      await restore(() async {
        await windowManager.maximize();
        await _waitFor(true, windowManager.isMaximized);
      });
    }
    if (snapshot.fullscreen) await restore(() => _fullscreen(true));
    if (failure != null) throw failure!;
    _pip = null;
  }

  Future<void> endSession() => _enqueue(() async {
    try {
      await _restorePip();
    } finally {
      try {
        if (_initialFullscreen != null) {
          await _fullscreen(_initialFullscreen!);
        }
      } finally {
        if (_initialAlwaysOnTop != null) {
          await windowManager.setAlwaysOnTop(_initialAlwaysOnTop!);
        }
        _initialFullscreen = null;
        _initialAlwaysOnTop = null;
      }
    }
  });

  @override
  void onWindowEnterFullScreen() {
    fullscreen = true;
    _completeFullscreen(true);
    _notify();
  }

  @override
  void onWindowLeaveFullScreen() {
    fullscreen = false;
    _completeFullscreen(false);
    _notify();
  }

  void _completeFullscreen(bool value) {
    final completion = _fullscreenCompletion;
    if (_fullscreenTarget == value &&
        completion != null &&
        !completion.isCompleted) {
      completion.complete();
    }
  }

  @override
  void onWindowFocus() {
    unawaited(refresh().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    super.dispose();
  }
}

class _PipWindowSnapshot {
  _PipWindowSnapshot({
    required this.fullscreen,
    required this.maximized,
    required this.alwaysOnTop,
    required this.bounds,
  });
  final bool fullscreen;
  final bool maximized;
  final bool alwaysOnTop;
  Rect bounds;
}

final playerWindowControllerProvider = Provider((ref) {
  final controller = PlayerWindowController();
  ref.onDispose(controller.dispose);
  return controller;
});
