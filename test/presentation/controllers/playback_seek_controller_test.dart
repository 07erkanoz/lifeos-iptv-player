import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/playback_seek_controller.dart';

void main() {
  late PlaybackSeekController controller;
  late List<Duration> seeks;
  var position = const Duration(seconds: 50);
  var duration = const Duration(seconds: 100);
  var errors = 0;

  setUp(() {
    position = const Duration(seconds: 50);
    duration = const Duration(seconds: 100);
    errors = 0;
    seeks = [];
    controller = PlaybackSeekController(
      position: () => position,
      duration: () => duration,
      seek: (target) async {
        seeks.add(target);
        position = target;
      },
      onPreview: (_) {},
      onError: () => errors++,
    );
  });
  tearDown(() => controller.dispose());

  test(
    'dragging previews every update but performs one seek on release',
    () async {
      for (var i = 0; i < 80; i++) {
        controller.updatePreview(Duration(seconds: i));
      }
      expect(seeks, isEmpty);
      expect(position.inSeconds, 50);
      expect(controller.preview?.inSeconds, 79);
      await controller.commitPreview();
      expect(seeks, [const Duration(seconds: 79)]);
      expect(controller.preview, isNull);
    },
  );

  test('repeated remote/button taps accumulate to one clamped seek', () async {
    for (var i = 0; i < 8; i++) {
      controller.nudge(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(seeks, isEmpty);
    expect(controller.preview, duration);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seeks, [duration]);
  });

  test(
    'negative and excessive targets stay within valid media duration',
    () async {
      await controller.commit(const Duration(seconds: -10));
      await controller.commit(const Duration(days: 1));
      expect(seeks, [Duration.zero, duration]);
    },
  );

  test(
    'unknown duration disables seeking rather than sending invalid targets',
    () async {
      duration = Duration.zero;
      controller.nudge(const Duration(seconds: 10));
      controller.updatePreview(const Duration(seconds: 10));
      await controller.commit(const Duration(seconds: 10));
      expect(seeks, isEmpty);
      expect(controller.preview, isNull);
    },
  );

  test('changing media cancels a pending remote seek', () async {
    controller.nudge(const Duration(seconds: 10));
    controller.cancel();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(seeks, isEmpty);
  });

  test('disposing cancels a pending seek', () async {
    controller.nudge(const Duration(seconds: 10));
    controller.dispose();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(seeks, isEmpty);
  });

  test(
    'pending native seeks are serialized and superseded targets skipped',
    () async {
      final firstSeek = Completer<void>();
      final started = Completer<void>();
      controller.dispose();
      controller = PlaybackSeekController(
        position: () => position,
        duration: () => duration,
        seek: (target) async {
          seeks.add(target);
          if (seeks.length == 1) {
            started.complete();
            await firstSeek.future;
          }
        },
        onPreview: (_) {},
        onError: () => errors++,
      );
      final first = controller.commit(const Duration(seconds: 20));
      await started.future;
      final obsolete = controller.commit(const Duration(seconds: 30));
      final latest = controller.commit(const Duration(seconds: 40));
      firstSeek.complete();
      await Future.wait([first, obsolete, latest]);
      expect(seeks.map((s) => s.inSeconds), [20, 40]);
    },
  );

  test('failed native seek clears preview and permits the next seek', () async {
    controller.dispose();
    var attempts = 0;
    controller = PlaybackSeekController(
      position: () => position,
      duration: () => duration,
      seek: (_) async {
        if (++attempts == 1) throw StateError('not seekable');
      },
      onPreview: (_) {},
      onError: () => errors++,
    );
    await controller.commit(const Duration(seconds: 10));
    expect(errors, 1);
    expect(controller.preview, isNull);
    await controller.commit(const Duration(seconds: 20));
    expect(attempts, 2);
  });
}
