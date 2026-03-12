import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/main.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_repository.g.dart';

class SettingsRepository {
  final SharedPreferences _prefs;

  SettingsRepository(this._prefs);

  static const _keyTheme = 'theme_mode';
  static const _keyLang = 'app_language';
  static const _keyHwAccel = 'hw_accel';
  static const _keyBuffer = 'buffer_duration';
  static const _keyStreamQuality = 'stream_quality';
  static const _keyDefaultAccount = 'default_account_id';
  static const _keyAutoNextEpisode = 'auto_next_episode';
  static const _keyAutoHideAdult = 'auto_hide_adult';
  static const _keyContinueWatching = 'continue_watching_enabled';
  static const _keyParentalEnabled = 'parental_control_enabled';
  static const _keyParentalPin = 'parental_pin';
  static const _keyOpenSubsApiKey = 'opensubtitles_api_key';
  static const _keySubtitleLang = 'subtitle_preferred_lang';
  static const _keySubtitleFontSize = 'subtitle_font_size';
  static const _keySubtitleColor = 'subtitle_color';
  static const _keySubtitleBold = 'subtitle_bold';
  static const _keySubtitleBg = 'subtitle_background_enabled';

  AppSettings loadSettings() {
    final themeIndex = _prefs.getInt(_keyTheme) ?? 2; // Default dark
    final langIndex = _prefs.getInt(_keyLang) ?? 0;
    final qualityIndex = _prefs.getInt(_keyStreamQuality) ?? 0; // Default auto

    return AppSettings(
      themeMode: AppThemeMode.values[themeIndex.clamp(0, AppThemeMode.values.length - 1)],
      language: AppLanguage.values[langIndex.clamp(0, AppLanguage.values.length - 1)],
      hardwareAcceleration: _prefs.getBool(_keyHwAccel) ?? true,
      bufferDuration: _prefs.getInt(_keyBuffer) ?? 30,
      streamQuality: StreamQuality.values[qualityIndex.clamp(0, StreamQuality.values.length - 1)],
      autoNextEpisode: _prefs.getBool(_keyAutoNextEpisode) ?? true,
      autoHideAdult: _prefs.getBool(_keyAutoHideAdult) ?? true,
      continueWatchingEnabled: _prefs.getBool(_keyContinueWatching) ?? true,
      parentalControlEnabled: _prefs.getBool(_keyParentalEnabled) ?? false,
      parentalPin: _prefs.getString(_keyParentalPin),
      opensubtitlesApiKey: _prefs.getString(_keyOpenSubsApiKey),
      subtitlePreferredLanguage: _prefs.getString(_keySubtitleLang) ?? 'tr',
      subtitleFontSize: _prefs.getInt(_keySubtitleFontSize) ?? 36,
      subtitleColor: _prefs.getString(_keySubtitleColor) ?? '#FFFFFF',
      subtitleBold: _prefs.getBool(_keySubtitleBold) ?? false,
      subtitleBackgroundEnabled: _prefs.getBool(_keySubtitleBg) ?? false,
      defaultAccountId: _prefs.getInt(_keyDefaultAccount),
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setInt(_keyTheme, settings.themeMode.index);
    await _prefs.setInt(_keyLang, settings.language.index);
    await _prefs.setBool(_keyHwAccel, settings.hardwareAcceleration);
    await _prefs.setInt(_keyBuffer, settings.bufferDuration);
    await _prefs.setInt(_keyStreamQuality, settings.streamQuality.index);
    await _prefs.setBool(_keyAutoNextEpisode, settings.autoNextEpisode);
    await _prefs.setBool(_keyAutoHideAdult, settings.autoHideAdult);
    await _prefs.setBool(_keyContinueWatching, settings.continueWatchingEnabled);
    await _prefs.setBool(_keyParentalEnabled, settings.parentalControlEnabled);
    if (settings.parentalPin != null) {
      await _prefs.setString(_keyParentalPin, settings.parentalPin!);
    }
    if (settings.opensubtitlesApiKey != null) {
      await _prefs.setString(_keyOpenSubsApiKey, settings.opensubtitlesApiKey!);
    }
    await _prefs.setString(_keySubtitleLang, settings.subtitlePreferredLanguage);
    await _prefs.setInt(_keySubtitleFontSize, settings.subtitleFontSize);
    await _prefs.setString(_keySubtitleColor, settings.subtitleColor);
    await _prefs.setBool(_keySubtitleBold, settings.subtitleBold);
    await _prefs.setBool(_keySubtitleBg, settings.subtitleBackgroundEnabled);
    if (settings.defaultAccountId != null) {
      await _prefs.setInt(_keyDefaultAccount, settings.defaultAccountId!);
    }
  }

  Future<void> setDefaultAccount(int accountId) async {
    await _prefs.setInt(_keyDefaultAccount, accountId);
  }
}

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsRepository(prefs);
}
