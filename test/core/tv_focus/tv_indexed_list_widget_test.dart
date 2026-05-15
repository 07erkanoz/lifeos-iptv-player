import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/tv_indexed_list.dart';
import 'package:lifeostv/core/tv_focus/tv_indexed_list_controller.dart';

class _Channel {
  final int id;
  final String name;
  const _Channel(this.id, this.name);
}

class _Harness {
  final TvIndexedListController controller;
  final List<_Channel> items;
  final List<int> activated;
  int leftCount;
  int rightCount;
  int topCount;
  int bottomCount;

  _Harness({required this.controller, required this.items})
      : activated = <int>[],
        leftCount = 0,
        rightCount = 0,
        topCount = 0,
        bottomCount = 0;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 500,
          child: TvIndexedList<_Channel>(
            controller: controller,
            items: items,
            channelIdOf: (c) => c.id,
            itemExtent: 60,
            onActivate: (c) => activated.add(c.id),
            onLeftEdge: () => leftCount++,
            onRightEdge: () => rightCount++,
            onTopEdge: () => topCount++,
            onBottomEdge: () => bottomCount++,
            itemBuilder: (ctx, c, focused) => Container(
              color: focused ? Colors.red : Colors.grey,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(c.name),
            ),
          ),
        ),
      ),
    );
  }
}

int? _focusedChannelId() {
  final label = FocusManager.instance.primaryFocus?.debugLabel;
  if (label == null || !label.startsWith('TvChannel_')) return null;
  return int.tryParse(label.substring('TvChannel_'.length));
}

void main() {
  late TvIndexedListController controller;
  late _Harness h;

  setUp(() {
    controller = TvIndexedListController();
    h = _Harness(
      controller: controller,
      items: List.generate(8, (i) => _Channel(200 + i, 'Channel $i')),
    );
  });

  group('TvIndexedList focus initialization', () {
    testWidgets('focusFirst lands on the first channel', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      expect(controller.focusFirst(), isTrue);
      await tester.pumpAndSettle();
      expect(_focusedChannelId(), 200);
    });

    testWidgets('controller picks up the channelIds + layout snapshot',
        (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      expect(controller.channelIds, List.generate(8, (i) => 200 + i));
      expect(controller.hasScrollController, isTrue);
    });
  });

  group('TvIndexedList D-pad up/down (no wrap)', () {
    testWidgets('arrow down moves to next channel', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusFirst();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedChannelId(), 201);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedChannelId(), 202);
    });

    testWidgets('arrow up moves to previous channel', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(3);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_focusedChannelId(), 202);
    });

    testWidgets('arrow up on first row fires onTopEdge', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusFirst();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(h.topCount, 1);
      expect(_focusedChannelId(), 200, reason: 'focus stays on row 0');
    });

    testWidgets('arrow down on last row fires onBottomEdge', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(7);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(h.bottomCount, 1);
      expect(_focusedChannelId(), 207);
    });
  });

  group('TvIndexedList edge callbacks (left/right)', () {
    testWidgets('arrow left fires onLeftEdge from any cell', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(3);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.leftCount, 1);
    });

    testWidgets('arrow right fires onRightEdge from any cell',
        (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(h.rightCount, 1);
    });
  });

  group('TvIndexedList activation', () {
    testWidgets('Enter on focused cell fires onActivate', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(4);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.activated, [204]);
    });
  });

  group('TvIndexedList focus restore', () {
    testWidgets('focusByChannelId returns to a known channel',
        (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(2);
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_focusedChannelId(), isNull);

      expect(controller.focusByChannelId(202), isTrue);
      await tester.pump();
      expect(_focusedChannelId(), 202);
    });

    testWidgets('focusCurrentOrFirst returns to lastFocused',
        (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(5);
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(controller.focusCurrentOrFirst(), isTrue);
      await tester.pump();
      expect(_focusedChannelId(), 205);
    });
  });
}
