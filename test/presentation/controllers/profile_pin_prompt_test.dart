import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/widgets/profile/profile_pin_prompt.dart';

void main() {
  testWidgets(
    'protected profile rejects wrong PIN, accepts correct PIN, disposes safely',
    (tester) async {
      bool? allowed;
      final profile = Profile(
        id: 2,
        name: 'Parent',
        avatarKey: 'default',
        isKids: false,
        pin: '1234',
        createdAt: DateTime(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  allowed = await confirmProfilePin(context, profile);
                },
                child: const Text('Switch profile'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Switch profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0000');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(allowed, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(allowed, true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
