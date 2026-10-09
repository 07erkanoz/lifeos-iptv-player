import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/framework_locale_delegates.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/locale_provider.dart';

void main() {
  test('UI and AI resolve system locale using the same supported language', () {
    expect(
      resolveAppLocale(AppLanguage.system, [const Locale('en', 'GB')]),
      const Locale('en'),
    );
    expect(
      resolveAppLocale(AppLanguage.system, [
        const Locale('ja'),
        const Locale('ar'),
      ]),
      const Locale('ar'),
    );
    expect(
      resolveAppLocale(AppLanguage.system, [const Locale('ja')]),
      const Locale('en'),
    );
    expect(
      resolveAppLocale(AppLanguage.ku, [const Locale('tr')]),
      const Locale('ku'),
    );
    expect(resolveAppTheme(AppThemeMode.system), ThemeMode.system);
  });
  for (final locale in appSupportedLocales) {
    testWidgets(
      '${locale.languageCode}: app and framework delegates load together',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: appSupportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              KurdishMaterialFallback(),
              KurdishCupertinoFallback(),
              KurdishWidgetsFallback(),
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    Text(AppLocalizations.of(context)!.play),
                    Text(MaterialLocalizations.of(context).backButtonTooltip),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Fixture'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final context = tester.element(find.byType(TextField));
        expect(Localizations.localeOf(context), locale);
        expect(
          Directionality.of(context),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      },
    );
  }
}
