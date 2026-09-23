import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/player_window_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  late _NativeWindow native;
  late PlayerWindowController controller;

  setUp(() {
    native = _NativeWindow();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.call);
    controller = PlayerWindowController();
  });

  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'fullscreen toggle waits for native completion before the next toggle',
    () async {
      await controller.beginSession();
      native.fullscreenDelay = const Duration(milliseconds: 60);
      final first = controller.toggleFullscreen();
      final second = controller.toggleFullscreen();
      await Future.wait([first, second]);
      expect(native.fullscreenRequests, [true, false]);
      expect(controller.fullscreen, isFalse);
      expect(controller.transitioning, isFalse);
    },
  );

  test(
    'AppKit completion event gates the next fullscreen transition',
    () async {
      controller.dispose();
      controller = PlayerWindowController(waitForFullscreenEvent: true);
      await controller.beginSession();
      final first = controller.toggleFullscreen();
      final second = controller.toggleFullscreen();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Native styleMask already changed; the animation has not completed yet.
      expect(native.fullscreen, isTrue);
      expect(native.fullscreenRequests, [true]);
      controller.onWindowEnterFullScreen();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(native.fullscreenRequests, [true, false]);
      controller.onWindowLeaveFullScreen();
      await second;
      expect(controller.fullscreen, isFalse);
    },
  );

  test('external fullscreen events update the control state', () {
    controller.onWindowEnterFullScreen();
    expect(controller.fullscreen, isTrue);
    controller.onWindowLeaveFullScreen();
    expect(controller.fullscreen, isFalse);
  });

  test(
    'PiP lowers the minimum and restores geometry, fullscreen and pinning',
    () async {
      native.fullscreen = true;
      native.pinned = true;
      final bounds = native.bounds;
      await controller.beginSession();
      await controller.enterPip();
      expect(native.minimum, const Size(380, 230));
      expect(native.bounds.size, const Size(380, 230));
      expect(native.fullscreen, isFalse);
      expect(native.pinned, isTrue);
      await controller.leavePip();
      expect(native.minimum, appWindowMinimumSize);
      expect(native.bounds, bounds);
      expect(native.fullscreen, isTrue);
      expect(native.pinned, isTrue);
    },
  );

  test(
    'maximized PiP session restores its normal bounds before maximizing',
    () async {
      native.maximized = true;
      await controller.beginSession();
      await controller.enterPip();
      expect(native.maximized, isFalse);
      await controller.leavePip();
      expect(native.maximized, isTrue);
      expect(native.minimum, appWindowMinimumSize);
    },
  );

  test(
    'PiP pinning does not overwrite the previous unpinned preference',
    () async {
      await controller.beginSession();
      await controller.enterPip();
      await controller.leavePip();
      expect(native.pinned, isFalse);
      await controller.toggleAlwaysOnTop();
      expect(controller.alwaysOnTop, isTrue);
      await controller.enterPip();
      await controller.leavePip();
      expect(controller.alwaysOnTop, isTrue);
      await controller.endSession();
      expect(native.pinned, isFalse);
    },
  );

  test(
    'failed shrink rolls back minimum size and original window state',
    () async {
      native.fullscreen = true;
      final bounds = native.bounds;
      await controller.beginSession();
      native.failNextBounds = true;
      await expectLater(
        controller.enterPip(),
        throwsA(isA<PlatformException>()),
      );
      expect(native.minimum, appWindowMinimumSize);
      expect(native.bounds, bounds);
      expect(native.fullscreen, isTrue);
      expect(native.pinned, isFalse);
      // A failed transition must not poison the serialized operation queue.
      await controller.enterPip();
      await controller.leavePip();
    },
  );

  test(
    'close queued during PiP entry restores before the next session starts',
    () async {
      await controller.beginSession();
      final enter = controller.enterPip();
      final close = controller.endSession();
      final next = controller.beginSession();
      await Future.wait([enter, close, next]);
      expect(native.minimum, appWindowMinimumSize);
      expect(native.pinned, isFalse);
      expect(native.bounds.size, const Size(1280, 720));
      await controller.toggleFullscreen();
      await controller.endSession();
      expect(native.fullscreen, isFalse);
    },
  );

  test(
    'route disposal cancels PiP entry before its queued callback runs',
    () async {
      final container = ProviderContainer(
        overrides: [
          playerWindowControllerProvider.overrideWithValue(controller),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(pipProvider.notifier);
      final player = _FakePlayer();
      await controller.beginSession();
      final enter = notifier.enterPip(
        player: player,
        controller: _FakeVideoController(),
        title: 'test',
        url: 'test',
      );
      final closing = controller.endSession();
      final releasing = notifier.releasePlayer(player);
      await Future.wait([enter, closing, releasing]);
      expect(container.read(pipProvider), isNull);
      expect(native.bounds.size, const Size(1280, 720));
      expect(native.minimum, appWindowMinimumSize);
      expect(native.pinned, isFalse);
    },
  );

  test(
    'route disposal during native PiP transition restores the window',
    () async {
      final container = ProviderContainer(
        overrides: [
          playerWindowControllerProvider.overrideWithValue(controller),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(pipProvider.notifier);
      final player = _FakePlayer();
      native.fullscreen = true;
      native.fullscreenDelay = const Duration(milliseconds: 60);
      await controller.beginSession();
      final enter = notifier.enterPip(
        player: player,
        controller: _FakeVideoController(),
        title: 'test',
        url: 'test',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final closing = controller.endSession();
      final releasing = notifier.releasePlayer(player);
      await Future.wait([enter, closing, releasing]);
      expect(container.read(pipProvider), isNull);
      expect(native.bounds.size, const Size(1280, 720));
      expect(native.minimum, appWindowMinimumSize);
      expect(native.pinned, isFalse);
      expect(native.fullscreen, isTrue);
    },
  );

  test('external pin changes are read before toggling', () async {
    await controller.beginSession();
    native.pinned = true;
    await controller.toggleAlwaysOnTop();
    expect(controller.alwaysOnTop, isFalse);
    expect(native.pinned, isFalse);
  });
}

class _NativeWindow {
  bool fullscreen = false;
  bool maximized = false;
  bool pinned = false;
  bool failNextBounds = false;
  Duration fullscreenDelay = Duration.zero;
  Rect bounds = const Rect.fromLTWH(80, 50, 1280, 720);
  Size minimum = appWindowMinimumSize;
  final fullscreenRequests = <bool>[];

  Future<Object?> call(MethodCall call) async {
    final args = (call.arguments as Map?) ?? {};
    switch (call.method) {
      case 'isFullScreen':
        return fullscreen;
      case 'isMaximized':
        return maximized;
      case 'isAlwaysOnTop':
        return pinned;
      case 'setFullScreen':
        final target = args['isFullScreen'] as bool;
        fullscreenRequests.add(target);
        // Simulate AppKit: method completion precedes the actual state change.
        if (fullscreenDelay != Duration.zero) {
          Timer(fullscreenDelay, () => fullscreen = target);
        } else {
          fullscreen = target;
        }
      case 'maximize':
        maximized = true;
      case 'unmaximize':
        maximized = false;
      case 'setAlwaysOnTop':
        pinned = args['isAlwaysOnTop'] as bool;
      case 'setMinimumSize':
        minimum = Size(args['width'] as double, args['height'] as double);
      case 'getBounds':
        return {
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        };
      case 'setBounds':
        if (failNextBounds) {
          failNextBounds = false;
          throw PlatformException(code: 'resize-failed');
        }
        bounds = Rect.fromLTWH(
          args['x'] as double? ?? bounds.left,
          args['y'] as double? ?? bounds.top,
          args['width'] as double? ?? bounds.width,
          args['height'] as double? ?? bounds.height,
        );
      default:
        throw UnsupportedError(call.method);
    }
    return null;
  }
}

class _FakePlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
