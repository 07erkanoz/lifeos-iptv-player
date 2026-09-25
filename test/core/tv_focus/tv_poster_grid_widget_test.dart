import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/tv_poster_grid.dart';
import 'package:lifeostv/core/tv_focus/tv_poster_grid_controller.dart';

/// Lightweight item model so tests don't depend on Drift's Channel class.
class _Item {
  final int streamId;
  final String label;
  const _Item(this.streamId, this.label);
}

/// Builds a small TvPosterGrid pumped into a MaterialApp + Scaffold so
/// Focus traversal has the standard ancestor chain it expects. Returns a
/// handle bundling the controller + activation log so each test can
/// inspect what fired.
class _Harness {
  final TvPosterGridController controller;
  final List<_Item> items;
  final List<int> activated;
  int leftEdgeCount;
  int topEdgeCount;
  final int columns;

  _Harness({
    required this.controller,
    required this.items,
    required this.columns,
  }) : activated = <int>[],
       leftEdgeCount = 0,
       topEdgeCount = 0;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // Wide enough for 4 columns × ~150px tiles + gaps.
          width: 800,
          // Tall enough for ~3 rows so all items mount without scrolling.
          height: 700,
          child: TvPosterGrid<_Item>(
            controller: controller,
            items: items,
            streamIdOf: (it) => it.streamId,
            columns: columns,
            childAspectRatio: 0.66,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            onActivate: (it) => activated.add(it.streamId),
            onLeftEdge: () => leftEdgeCount++,
            onTopEdge: () => topEdgeCount++,
            itemBuilder: (ctx, it, isFocused) => Container(
              key: ValueKey('tile-${it.streamId}'),
              color: isFocused ? Colors.red : Colors.grey,
              alignment: Alignment.center,
              child: Text(it.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns the streamId of the currently focused tile, or null if focus is
/// elsewhere. _TvPosterItem creates its FocusNode with a debugLabel of
/// `TvPoster_<streamId>`, so we can read that off primaryFocus directly —
/// the visual tile is a descendant of the Focus widget, not an ancestor,
/// so a tree walk in either direction is more brittle than this.
int? _focusedStreamId() {
  final label = FocusManager.instance.primaryFocus?.debugLabel;
  if (label == null || !label.startsWith('TvPoster_')) return null;
  return int.tryParse(label.substring('TvPoster_'.length));
}

void main() {
  late TvPosterGridController controller;
  late _Harness h;

  setUp(() {
    controller = TvPosterGridController();
    h = _Harness(
      controller: controller,
      columns: 4,
      items: List.generate(10, (i) => _Item(100 + i, 'Item $i')),
    );
  });

  group('TvPosterGrid focus initialization', () {
    testWidgets('focusFirst lands on the first mounted item', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();

      expect(controller.focusFirst(), isTrue);
      await tester.pumpAndSettle();
      expect(_focusedStreamId(), 100);
    });

    testWidgets('items mount their FocusNodes with the controller', (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      await tester.pump();

      // controller knows the list order
      expect(controller.streamIds, List.generate(10, (i) => 100 + i));
      // controller has captured the layout snapshot
      expect(controller.columns, 4);
      expect(controller.hasScrollController, isTrue);
    });

    testWidgets('new category focuses its first poster after an async gap', (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(5);
      await tester.pump();
      expect(_focusedStreamId(), 105);

      // Category changes can temporarily remove the old grid while data
      // loads. The focus request must wait for the replacement Focus widgets.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      expect(controller.focusFirst(), isFalse);

      h = _Harness(
        controller: controller,
        columns: 4,
        items: List.generate(8, (i) => _Item(200 + i, 'New $i')),
      );
      await tester.pumpWidget(h.build());
      await tester.pumpAndSettle();
      expect(_focusedStreamId(), 200);
    });

    testWidgets(
      'detail return restores the previous poster after grid remount',
      (tester) async {
        await tester.pumpWidget(h.build());
        await tester.pump();
        controller.focusIndex(5);
        await tester.pump();
        expect(_focusedStreamId(), 105);

        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pump();
        expect(controller.focusCurrentOrFirst(), isFalse);
        await tester.pumpWidget(h.build());
        await tester.pumpAndSettle();
        expect(_focusedStreamId(), 105);
      },
    );
  });

  group('TvPosterGrid D-pad navigation (row-major, no wrap)', () {
    testWidgets('arrow right moves within a row', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusFirst();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_focusedStreamId(), 101);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_focusedStreamId(), 102);
    });

    testWidgets('arrow left moves backwards within a row', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(2); // streamId 102
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_focusedStreamId(), 101);
    });

    testWidgets('arrow down moves to same column in next row', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(1); // row 0, col 1
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // 4 columns → +4 indices = streamId 105 (row 1, col 1)
      expect(_focusedStreamId(), 105);
    });

    testWidgets('arrow up moves to same column in previous row', (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(5); // row 1, col 1
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_focusedStreamId(), 101); // row 0, col 1
    });

    testWidgets('arrow right at row end is a no-op (no wrap)', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(3); // row 0, col 3 (last column)
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // Should NOT have wrapped to streamId 104 (row 1, col 0).
      expect(_focusedStreamId(), 103);
    });

    testWidgets('arrow down on partial last row is a no-op', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      // 10 items / 4 columns → row 0 [100..103], row 1 [104..107], row 2 [108,109]
      // Focus index 5 (row 1, col 1). Going down: index 9 doesn't exist
      // in col 1 (last row only has col 0 + 1).
      // Actually row 2 has indices 8, 9 → cols 0, 1. So col 1 DOES exist.
      // Pick col 2 (index 6) which has no row 2 counterpart.
      controller.focusIndex(6); // row 1, col 2
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // No row 2 col 2 → no-op
      expect(_focusedStreamId(), 106);
    });
  });

  group('TvPosterGrid edge callbacks', () {
    testWidgets('arrow left at column 0 fires onLeftEdge', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusFirst(); // index 0, col 0
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(h.leftEdgeCount, 1);
      // Focus stays where it was — onLeftEdge is responsible for moving
      // it to the category sidebar.
      expect(_focusedStreamId(), 100);
    });

    testWidgets('arrow up on top row fires onTopEdge', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(2); // row 0, col 2
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(h.topEdgeCount, 1);
      expect(_focusedStreamId(), 102);
    });
  });

  group('TvPosterGrid activation', () {
    testWidgets('select/enter fires onActivate with the focused item', (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(3);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.activated, [103]);
    });
  });

  group('TvPosterGridController focus restore', () {
    testWidgets('focusByStreamId restores after another item was focused', (
      tester,
    ) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(0);
      await tester.pump();
      controller.focusIndex(7);
      await tester.pump();
      expect(controller.lastFocusedStreamId, 107);

      // Move focus away (simulate detail open clobbering focus).
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_focusedStreamId(), isNull);

      // Restore.
      expect(controller.focusByStreamId(107), isTrue);
      await tester.pump();
      expect(_focusedStreamId(), 107);
    });

    testWidgets('focusCurrentOrFirst returns to lastFocused', (tester) async {
      await tester.pumpWidget(h.build());
      await tester.pump();
      controller.focusIndex(4);
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(controller.focusCurrentOrFirst(), isTrue);
      await tester.pump();
      expect(_focusedStreamId(), 104);
    });
  });
}
