import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/controllers/episode_playlist.dart';

void main() {
  EpisodeNavigator navigator() => EpisodeNavigator(
    EpisodePlaylist([
      const EpisodeSource(
        streamId: 11,
        url: 'https://example.invalid/1',
        title: 'E1',
      ),
      const EpisodeSource(
        streamId: 12,
        url: 'https://example.invalid/2',
        title: 'E2',
      ),
    ], 0),
  );
  test('save keeps old identity, overlapping navigation is rejected', () async {
    final n = navigator(), gate = Completer<void>();
    final seen = <int>[];
    final first = n.move(
      1,
      save: () async {
        seen.add(n.current.streamId);
        await gate.future;
      },
      open: (source) async {
        seen.add(source.streamId);
      },
    );
    expect(await n.move(1, save: () async {}, open: (_) async {}), false);
    gate.complete();
    expect(await first, true);
    expect(seen, [11, 12]);
    expect(await n.move(1, save: () async {}, open: (_) async {}), false);
    expect(await n.move(-1, save: () async {}, open: (_) async {}), true);
    expect(n.current.streamId, 11);
  });
  test('closing during save prevents any new source from opening', () async {
    final n = navigator(), gate = Completer<void>();
    var opened = false;
    final next = n.move(
      1,
      save: () => gate.future,
      open: (_) async {
        opened = true;
      },
    );
    n.close();
    gate.complete();
    expect(await next, false);
    expect(opened, false);
    expect(n.index, 0);
  });
  test(
    'failed save leaves the identity unchanged and releases navigation',
    () async {
      final n = navigator();
      await expectLater(
        n.move(
          1,
          save: () async {
            throw StateError('failed');
          },
          open: (_) async {},
        ),
        throwsStateError,
      );
      expect(n.current.streamId, 11);
      expect(n.switching, false);
    },
  );
}
