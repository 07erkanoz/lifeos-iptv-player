enum AppThemeMode { system, light, dark }
enum AppLanguage { system, en, tr, de, fr, es, ar, ru, ku }
enum StreamQuality { auto, high, medium, low }

class AppSettings {
  final AppThemeMode themeMode;
  final AppLanguage language;

  // Player Settings
  final bool hardwareAcceleration;
  final bool autoSubs;
  final int bufferDuration; // seconds
  final StreamQuality streamQuality;
  final bool autoNextEpisode;

  // EPG Settings
  final int epgPastDays;

  // Parental / Adult Filter
  final bool parentalControlEnabled;
  final String? parentalPin;
  final bool autoHideAdult;

  // Content
  final bool continueWatchingEnabled;

  // OpenSubtitles
  final String? opensubtitlesApiKey;
  final String subtitlePreferredLanguage; // ISO 639-1 code (e.g., 'tr', 'en')

  // Subtitle appearance
  final int subtitleFontSize;
  final String subtitleColor; // hex e.g. '#FFFFFF'
  final bool subtitleBold;
  final bool subtitleBackgroundEnabled;

  // Account
  final int? defaultAccountId;

  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.language = AppLanguage.system,
    this.hardwareAcceleration = true,
    this.autoSubs = false,
    this.bufferDuration = 30,
    this.streamQuality = StreamQuality.auto,
    this.autoNextEpisode = true,
    this.epgPastDays = 3,
    this.parentalControlEnabled = false,
    this.parentalPin,
    this.autoHideAdult = true,
    this.continueWatchingEnabled = true,
    this.opensubtitlesApiKey,
    this.subtitlePreferredLanguage = 'tr',
    this.subtitleFontSize = 36,
    this.subtitleColor = '#FFFFFF',
    this.subtitleBold = false,
    this.subtitleBackgroundEnabled = false,
    this.defaultAccountId,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    bool? hardwareAcceleration,
    bool? autoSubs,
    int? bufferDuration,
    StreamQuality? streamQuality,
    bool? autoNextEpisode,
    int? epgPastDays,
    bool? parentalControlEnabled,
    String? parentalPin,
    bool? autoHideAdult,
    bool? continueWatchingEnabled,
    String? opensubtitlesApiKey,
    String? subtitlePreferredLanguage,
    int? subtitleFontSize,
    String? subtitleColor,
    bool? subtitleBold,
    bool? subtitleBackgroundEnabled,
    int? defaultAccountId,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      autoSubs: autoSubs ?? this.autoSubs,
      bufferDuration: bufferDuration ?? this.bufferDuration,
      streamQuality: streamQuality ?? this.streamQuality,
      autoNextEpisode: autoNextEpisode ?? this.autoNextEpisode,
      epgPastDays: epgPastDays ?? this.epgPastDays,
      parentalControlEnabled: parentalControlEnabled ?? this.parentalControlEnabled,
      parentalPin: parentalPin ?? this.parentalPin,
      autoHideAdult: autoHideAdult ?? this.autoHideAdult,
      continueWatchingEnabled: continueWatchingEnabled ?? this.continueWatchingEnabled,
      opensubtitlesApiKey: opensubtitlesApiKey ?? this.opensubtitlesApiKey,
      subtitlePreferredLanguage: subtitlePreferredLanguage ?? this.subtitlePreferredLanguage,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      subtitleBold: subtitleBold ?? this.subtitleBold,
      subtitleBackgroundEnabled: subtitleBackgroundEnabled ?? this.subtitleBackgroundEnabled,
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
    );
  }
}
