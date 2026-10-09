import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/widgets/player/player_controls_layout.dart';
import 'package:lifeostv/presentation/widgets/player/responsive_player_toolbar.dart';

void main() {
  testWidgets('pause panel cannot lift footer at any tested window height', (
    tester,
  ) async {
    for (final width in [320.0, 770.0]) {
      for (final height in [720.0, 360.0, 240.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        for (final panelHeight in [0.0, 154.0, 600.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PlayerControlsLayout(
                  topBar: const SizedBox(height: 56),
                  infoPanel: panelHeight == 0
                      ? null
                      : SizedBox(height: panelHeight),
                  bottomBar: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ResponsivePlayerToolbar(
                      key: const ValueKey('footer'),
                      actions: [
                        for (var i = 0; i < 14; i++)
                          PlayerToolbarAction(
                            id: '$i',
                            label: 'Control $i',
                            icon: Icons.play_arrow,
                            onPressed: () {},
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.byKey(const ValueKey('footer'))).bottom,
            height - 16,
          );
        }
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
