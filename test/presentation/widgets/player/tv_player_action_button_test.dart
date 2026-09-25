import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/presentation/widgets/player/tv_player_action_button.dart';

void main() {
  testWidgets('D-pad moves between TV controls and Select activates them', (
    tester,
  ) async {
    final audioFocus = FocusNode();
    final subtitleFocus = FocusNode();
    addTearDown(audioFocus.dispose);
    addTearDown(subtitleFocus.dispose);
    var selected = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Row(
            children: [
              TvPlayerActionButton(
                icon: Icons.audiotrack,
                label: 'Audio',
                focusNode: audioFocus,
                onPressed: () => selected = 'audio',
              ),
              TvPlayerActionButton(
                icon: Icons.subtitles,
                label: 'Subtitles',
                focusNode: subtitleFocus,
                onPressed: () => selected = 'subtitles',
              ),
            ],
          ),
        ),
      ),
    );

    audioFocus.requestFocus();
    await tester.pump();
    expect(audioFocus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(subtitleFocus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, 'subtitles');
  });
}
