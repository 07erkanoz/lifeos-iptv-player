import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/widgets/player/channel_list_overlay.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';

void main() {
  testWidgets('category and empty search cannot activate a hidden channel', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChannelListOverlay(
            channels: const [
              PlayerChannel(
                streamId: 1,
                name: 'Alpha',
                url: 'https://example.invalid/1',
                categoryId: 'A',
              ),
              PlayerChannel(
                streamId: 2,
                name: 'Beta',
                url: 'https://example.invalid/2',
                categoryId: 'B',
              ),
            ],
            currentChannelIndex: 1,
            onChannelSelected: picked.add,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, [0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, [0]);
    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(picked, [0, 0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
