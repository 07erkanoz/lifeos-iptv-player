import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Flutter does not provide Kurdish framework translations. Keep the app's
// Kurdish ARB strings while providing English framework labels and LTR layout.
// These delegates only claim ku; all other locales use Flutter's delegates.
class KurdishMaterialFallback
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KurdishMaterialFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(KurdishMaterialFallback old) => false;
}

class KurdishCupertinoFallback
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const KurdishCupertinoFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(KurdishCupertinoFallback old) => false;
}

class KurdishWidgetsFallback
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const KurdishWidgetsFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(KurdishWidgetsFallback old) => false;
}
