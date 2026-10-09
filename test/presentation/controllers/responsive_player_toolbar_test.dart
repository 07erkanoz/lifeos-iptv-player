import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/widgets/player/responsive_player_toolbar.dart';

void main() {
  testWidgets('all controls remain visible across desktop and phone widths', (
    tester,
  ) async {
    for (final touch in [false, true]) {
      for (final width in [240.0, 320.0, 480.0, 770.0, 1000.0, 1400.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 400);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomLeft,
                child: ResponsivePlayerToolbar(
                  touch: touch,
                  actions: [
                    for (var i = 0; i < 14; i++)
                      PlayerToolbarAction(
                        id: '$i',
                        label: 'A long localized control label $i',
                        icon: Icons.play_arrow,
                        primary: i == 0,
                        showLabel: i > 4 && i < 9,
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$width / touch=$touch');
        for (var i = 0; i < 14; i++) {
          final rect = tester.getRect(find.byKey(ValueKey('player-action-$i')));
          expect(rect.left, greaterThanOrEqualTo(-0.1));
          expect(rect.right, lessThanOrEqualTo(width + 0.1));
          expect(rect.bottom, lessThanOrEqualTo(400));
          expect(rect.top, greaterThanOrEqualTo(0));
          if (touch) expect(rect.width, greaterThanOrEqualTo(44));
        }
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
  testWidgets('resize preserves the focused control and keyboard activation', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var activated = 0;
    for (final width in [1400.0, 770.0, 320.0, 1000.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 400);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsivePlayerToolbar(
              actions: [
                for (var i = 0; i < 14; i++)
                  PlayerToolbarAction(
                    id: '$i',
                    label: 'Audio track $i',
                    icon: Icons.audiotrack,
                    focusNode: i == 5 ? focus : null,
                    showLabel: true,
                    onPressed: () => activated++,
                  ),
              ],
            ),
          ),
        ),
      );
      if (width == 1400) focus.requestFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, focus);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(activated, 4);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
  testWidgets('Arabic direction and enlarged text do not clip buttons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(770, 400);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ResponsivePlayerToolbar(
                actions: [
                  for (var i = 0; i < 14; i++)
                    PlayerToolbarAction(
                      id: '$i',
                      label: 'اختيار لغة الصوت والترجمة',
                      icon: Icons.audiotrack,
                      showLabel: true,
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 14; i++) {
      final rect = tester.getRect(find.byKey(ValueKey('player-action-$i')));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(770));
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
