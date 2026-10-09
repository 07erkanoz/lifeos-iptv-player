import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

const appSupportedLocales = [
  Locale('en'),
  Locale('tr'),
  Locale('de'),
  Locale('fr'),
  Locale('es'),
  Locale('ar'),
  Locale('ru'),
  Locale('ku'),
];

Locale resolveAppLocale(AppLanguage language, Iterable<Locale> deviceLocales) {
  if (language != AppLanguage.system) return Locale(language.name);
  for (final device in deviceLocales) {
    for (final supported in appSupportedLocales) {
      if (device.languageCode == supported.languageCode) return supported;
    }
  }
  return const Locale('en');
}

final resolvedLocaleProvider = Provider<Locale>((ref) {
  return resolveAppLocale(
    ref.watch(settingsProvider.select((s) => s.language)),
    WidgetsBinding.instance.platformDispatcher.locales,
  );
});

ThemeMode resolveAppTheme(AppThemeMode theme) => switch (theme) {
  AppThemeMode.system => ThemeMode.system,
  AppThemeMode.light => ThemeMode.light,
  AppThemeMode.dark => ThemeMode.dark,
};
