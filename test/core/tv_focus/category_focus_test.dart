import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/core/tv_focus/category_focus.dart';

void main() {
  testWidgets('detached selected category falls back to visible row', (
    tester,
  ) async {
    final selected = FocusNode();
    final fallback = FocusNode();
    addTearDown(selected.dispose);
    addTearDown(fallback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Focus(focusNode: selected, child: const Text('Selected')),
            Focus(focusNode: fallback, child: const Text('Favorites')),
          ],
        ),
      ),
    );
    expect(focusMountedCategory(selected, fallback), isTrue);
    await tester.pump();
    expect(selected.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: fallback, child: const Text('Favorites')),
      ),
    );
    expect(selected.context?.mounted, isFalse);
    expect(focusMountedCategory(selected, fallback), isTrue);
    await tester.pump();
    expect(fallback.hasPrimaryFocus, isTrue);
  });
}
