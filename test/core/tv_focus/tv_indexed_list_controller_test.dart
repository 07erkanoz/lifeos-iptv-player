import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/tv_indexed_list_controller.dart';

void main() {
  late TvIndexedListController controller;

  setUp(() {
    controller = TvIndexedListController();
  });

  group('TvIndexedListController state defaults', () {
    test('starts empty and detached', () {
      expect(controller.itemCount, 0);
      expect(controller.lastFocusedChannelId, -1);
      expect(controller.hasScrollController, isFalse);
      expect(controller.channelIds, isEmpty);
    });

    test('focusFirst / focusByChannelId return false when empty', () {
      expect(controller.focusFirst(), isFalse);
      expect(controller.focusByChannelId(42), isFalse);
      expect(controller.focusIndex(0), isFalse);
    });
  });

  group('TvIndexedListController attach', () {
    test('attach stores layout snapshot + channel list', () {
      final scroll = ScrollController();
      controller.attach(
        scrollController: scroll,
        itemHeight: 80,
        paddingTop: 12,
        channelIds: const [101, 102, 103],
      );
      expect(controller.itemCount, 3);
      expect(controller.channelIds, [101, 102, 103]);
      expect(controller.hasScrollController, isTrue);
      scroll.dispose();
    });

    test('detach only clears the matching scrollController', () {
      final scroll = ScrollController();
      final stale = ScrollController();
      controller.attach(
        scrollController: scroll,
        itemHeight: 80,
        paddingTop: 0,
        channelIds: const [],
      );
      // A stale (previous frame's) controller must not wipe the live
      // attachment.
      controller.detach(stale);
      expect(controller.hasScrollController, isTrue);
      controller.detach(scroll);
      expect(controller.hasScrollController, isFalse);
      scroll.dispose();
      stale.dispose();
    });
  });

  group('TvIndexedListController item registration', () {
    test('registerItem + unregisterItem identity-checked', () {
      final node = FocusNode();
      final stale = FocusNode();
      controller.registerItem(7, node);
      controller.unregisterItem(7, stale); // stale → no-op
      controller.notifyFocused(7);
      expect(controller.lastFocusedChannelId, 7);
      node.dispose();
      stale.dispose();
    });

    test('notifyFocused updates lastFocusedChannelId', () {
      controller.notifyFocused(99);
      expect(controller.lastFocusedChannelId, 99);
      controller.notifyFocused(100);
      expect(controller.lastFocusedChannelId, 100);
    });
  });

  group('TvIndexedListController focus delivery', () {
    testWidgets(
      'focusByChannelId synchronously focuses a mounted node',
      (tester) async {
        final node = FocusNode();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Focus(focusNode: node, child: const SizedBox()),
          ),
        );

        controller.attach(
          scrollController: ScrollController(),
          itemHeight: 80,
          paddingTop: 0,
          channelIds: const [42],
        );
        controller.registerItem(42, node);

        expect(controller.focusByChannelId(42), isTrue);
        await tester.pump();
        expect(node.hasFocus, isTrue);
      },
    );

    test('focusByChannelId returns false for unknown channelId', () {
      controller.attach(
        scrollController: ScrollController(),
        itemHeight: 80,
        paddingTop: 0,
        channelIds: const [1, 2, 3],
      );
      expect(controller.focusByChannelId(999), isFalse);
    });

    test(
      'focusByChannelId for known-but-unmounted channelId returns true',
      () {
        controller.attach(
          scrollController: ScrollController(),
          itemHeight: 80,
          paddingTop: 0,
          channelIds: const [1, 2, 3],
        );
        // No registerItem calls → all items "unmounted" from
        // controller's POV. Should still accept the request and
        // schedule a retry rather than refuse.
        expect(controller.focusByChannelId(2), isTrue);
      },
    );

    test(
      'focusCurrentOrFirst falls back to first when lastFocused dropped '
      'out of the list',
      () {
        controller.attach(
          scrollController: ScrollController(),
          itemHeight: 80,
          paddingTop: 0,
          channelIds: const [10, 20, 30],
        );
        controller.notifyFocused(20);

        // Filter changes: 20 disappears.
        controller.attach(
          scrollController: ScrollController(),
          itemHeight: 80,
          paddingTop: 0,
          channelIds: const [10, 30],
        );

        expect(controller.focusCurrentOrFirst(), isTrue);
        expect(controller.channelIds.first, 10);
      },
    );
  });
}
