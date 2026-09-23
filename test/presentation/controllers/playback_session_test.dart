import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/playback_session.dart';

void main() {
  test(
    'closing during initialization never opens media and disposes once',
    () async {
      final setup = Completer<void>();
      final started = Completer<void>();
      final opened = <String>[];
      var disposed = 0;
      final session = PlaybackSession(
        initialize: () {
          started.complete();
          return setup.future;
        },
        openMedia: (url) async => opened.add(url),
        disposePlayer: () async => disposed++,
      );
      final opening = session.open('first');
      await started.future;
      final closing = session.close();
      expect(session.isClosed, isTrue);
      expect(disposed, 0);
      setup.complete();
      expect(await opening, isFalse);
      await closing;
      await session.close();
      expect(await session.open('after-close'), isFalse);
      expect(opened, isEmpty);
      expect(disposed, 1);
    },
  );

  test('channel changes during setup open only the newest request', () async {
    final setup = Completer<void>();
    final started = Completer<void>();
    final opened = <String>[];
    var setups = 0;
    final session = PlaybackSession(
      initialize: () {
        setups++;
        started.complete();
        return setup.future;
      },
      openMedia: (url) async => opened.add(url),
      disposePlayer: () async {},
    );
    final first = session.open('first');
    await started.future;
    final second = session.open('second');
    final third = session.open('third');
    setup.complete();
    expect(await Future.wait([first, second, third]), [false, false, true]);
    expect(opened, ['third']);
    expect(setups, 1);
    await session.close();
  });

  test(
    'dispose waits for an in-flight open, skips queued replacements',
    () async {
      final opening = Completer<void>();
      final started = Completer<void>();
      final calls = <String>[];
      final session = PlaybackSession(
        initialize: () async {},
        openMedia: (url) {
          calls.add(url);
          started.complete();
          return opening.future;
        },
        disposePlayer: () async => calls.add('dispose'),
      );
      final first = session.open('first');
      await started.future;
      final replacement = session.open('replacement');
      final close = session.close();
      expect(calls, ['first']);
      opening.complete();
      await Future.wait([first, replacement]);
      await close;
      expect(calls, ['first', 'dispose']);
    },
  );

  test('failed open does not poison retry or disposal', () async {
    var attempts = 0;
    var disposed = false;
    final session = PlaybackSession(
      initialize: () async {},
      openMedia: (_) async {
        if (++attempts == 1) throw StateError('failure');
      },
      disposePlayer: () async => disposed = true,
    );
    await expectLater(session.open('first'), throwsStateError);
    expect(await session.open('retry'), isTrue);
    await session.close();
    expect(disposed, isTrue);
  });

  test(
    'failed initialization can be retried without opening unconfigured media',
    () async {
      var attempts = 0;
      final opened = <String>[];
      final session = PlaybackSession(
        initialize: () async {
          if (++attempts == 1) throw StateError('setup');
        },
        openMedia: (url) async => opened.add(url),
        disposePlayer: () async {},
      );
      await expectLater(session.open('first'), throwsStateError);
      expect(opened, isEmpty);
      expect(await session.open('retry'), isTrue);
      expect(opened, ['retry']);
      await session.close();
    },
  );
}
