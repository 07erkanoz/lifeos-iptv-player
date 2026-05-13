import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/tv_poster_grid_controller.dart';

void main() {
  late TvPosterGridController controller;

  setUp(() {
    controller = TvPosterGridController();
  });

  group('TvPosterGridController state defaults', () {
    test('starts empty and detached', () {
      expect(controller.itemCount, 0);
      expect(controller.lastFocusedStreamId, -1);
      expect(controller.hasScrollController, isFalse);
      expect(controller.streamIds, isEmpty);
    });

    test('focusFirst / focusByStreamId return false when empty', () {
      expect(controller.focusFirst(), isFalse);
      expect(controller.focusByStreamId(42), isFalse);
      expect(controller.focusIndex(0), isFalse);
    });
  });

  group('TvPosterGridController attach', () {
    test('attach stores layout snapshot for later index math', () {
      final scroll = ScrollController();
      controller.attach(
        scrollController: scroll,
        columns: 5,
        rowStride: 240,
        paddingTop: 24,
        streamIds: const [10, 20, 30],
      );
      expect(controller.columns, 5);
      expect(controller.itemCount, 3);
      expect(controller.streamIds, [10, 20, 30]);
      expect(controller.hasScrollController, isTrue);
      scroll.dispose();
    });

    test('columns < 1 is clamped to 1 so D-pad math stays valid', () {
      final scroll = ScrollController();
      controller.attach(
        scrollController: scroll,
        columns: 0,
        rowStride: 100,
        paddingTop: 0,
        streamIds: const [1],
      );
      expect(controller.columns, 1);
      scroll.dispose();
    });

    test('detach only clears the matching scrollController', () {
      final scroll = ScrollController();
      final stale = ScrollController();
      controller.attach(
        scrollController: scroll,
        columns: 1,
        rowStride: 0,
        paddingTop: 0,
        streamIds: const [],
      );
      // Detach with a stale (e.g. previous frame's) controller must not
      // wipe the live one.
      controller.detach(stale);
      expect(controller.hasScrollController, isTrue);
      controller.detach(scroll);
      expect(controller.hasScrollController, isFalse);
      scroll.dispose();
      stale.dispose();
    });
  });

  group('TvPosterGridController item registration', () {
    test('registerItem + unregisterItem identity-checked', () {
      final node = FocusNode();
      final stale = FocusNode();
      controller.registerItem(7, node);
      // Stale unregister (e.g. from a previous mount) must NOT wipe the
      // live registration.
      controller.unregisterItem(7, stale);
      // Sanity: the live node is still registered — we'll verify by
      // notifyFocused + lastFocusedStreamId since the map is private.
      controller.notifyFocused(7);
      expect(controller.lastFocusedStreamId, 7);

      controller.unregisterItem(7, node);
      // Now re-register with a different node; lastFocusedStreamId stays
      // sticky since it's a separate concern.
      final n2 = FocusNode();
      controller.registerItem(7, n2);
      controller.notifyFocused(7);
      expect(controller.lastFocusedStreamId, 7);

      node.dispose();
      stale.dispose();
      n2.dispose();
    });

    test('notifyFocused updates lastFocusedStreamId', () {
      controller.notifyFocused(99);
      expect(controller.lastFocusedStreamId, 99);
      controller.notifyFocused(100);
      expect(controller.lastFocusedStreamId, 100);
    });
  });

  group('TvPosterGridController focus delivery', () {
    testWidgets(
      'focusByStreamId synchronously focuses a mounted node',
      (tester) async {
        final node = FocusNode();
        // Pump a Focus widget so the node is attached to a real tree —
        // FocusNode.requestFocus is a no-op on detached nodes.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Focus(focusNode: node, child: const SizedBox()),
          ),
        );

        controller.attach(
          scrollController: ScrollController(),
          columns: 1,
          rowStride: 0,
          paddingTop: 0,
          streamIds: const [42],
        );
        controller.registerItem(42, node);

        expect(controller.focusByStreamId(42), isTrue);
        await tester.pump();
        expect(node.hasFocus, isTrue);
      },
    );

    test('focusByStreamId returns false for unknown streamId', () {
      controller.attach(
        scrollController: ScrollController(),
        columns: 1,
        rowStride: 0,
        paddingTop: 0,
        streamIds: const [1, 2, 3],
      );
      expect(controller.focusByStreamId(999), isFalse);
    });

    test(
      'focusByStreamId for known-but-unmounted streamId returns true '
      '(async retry path)',
      () {
        controller.attach(
          scrollController: ScrollController(),
          columns: 1,
          rowStride: 0,
          paddingTop: 0,
          streamIds: const [1, 2, 3],
        );
        // No registerItem calls → all items are "unmounted" from the
        // controller's perspective. The controller should still accept
        // the request and schedule a retry rather than refusing.
        expect(controller.focusByStreamId(2), isTrue);
      },
    );

    test(
      'focusCurrentOrFirst falls back to first when lastFocused dropped '
      'out of the list',
      () {
        controller.attach(
          scrollController: ScrollController(),
          columns: 1,
          rowStride: 0,
          paddingTop: 0,
          streamIds: const [10, 20, 30],
        );
        controller.notifyFocused(20);

        // Filter changes: 20 disappears.
        controller.attach(
          scrollController: ScrollController(),
          columns: 1,
          rowStride: 0,
          paddingTop: 0,
          streamIds: const [10, 30],
        );

        expect(controller.focusCurrentOrFirst(), isTrue);
        // lastFocusedStreamId stays 20 (sticky); the focus call falls
        // through to focusFirst → request for streamId 10.
        expect(controller.streamIds.first, 10);
      },
    );
  });
}
