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

  // Skip-Intro UX. When true and the user has marked this series'
  // intro range, the player overlays a "Skip Intro" floating button
  // whenever playback is inside that range.
  final bool showSkipIntroButton;

  // OpenSubtitles
  final String? opensubtitlesApiKey;

  // Google AI Studio (Gemini) API key. Optional — when set, unlocks
  // the AI assistant features (natural-language search, "what should
  // I watch tonight?" chat, spoiler-free recaps, plot summarisation,
  // smart subtitle translation). When null/empty, every AI surface
  // hides itself and the rest of the app keeps working exactly as
  // before. Read by [AppSettings.hasAiKey] so callers don't have to
  // repeat the empty-string check.
  final String? geminiApiKey;
  final String subtitlePreferredLanguage; // ISO 639-1 code (e.g., 'tr', 'en')

  // Subtitle appearance
  final int subtitleFontSize;
  final String subtitleColor; // hex e.g. '#FFFFFF'
  final bool subtitleBold;
  final bool subtitleBackgroundEnabled;

  // Remember last chosen audio/subtitle track across episodes.
  // We store BOTH the track's `language` and `title` because:
  //   - Some streams expose only one of the two
  //   - Episode N's track may carry the label in `language` while
  //     episode N+1 has the same label in `title` (or vice versa)
  // Numeric track ids are unstable across Player instances, so we
  // can't fall back on them. The matcher in
  // lib/data/services/subtitle_track_matcher.dart canonicalizes both
  // sides through an ISO 639-1↔2 map and a parenthetical-qualifier
  // stripper so "tr" / "tur" / "Türkçe" / "Turkish (forced)" all
  // collapse to the same canonical key.
  final String? lastPlayerAudioLanguage;
  final String? lastPlayerAudioTitle;
  final String? lastPlayerSubtitleLanguage;
  final String? lastPlayerSubtitleTitle;

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
    this.showSkipIntroButton = true,
    this.opensubtitlesApiKey,
    this.geminiApiKey,
    this.subtitlePreferredLanguage = 'tr',
    this.subtitleFontSize = 55,
    this.subtitleColor = '#FFFFFF',
    this.subtitleBold = false,
    this.subtitleBackgroundEnabled = false,
    this.lastPlayerAudioLanguage,
    this.lastPlayerAudioTitle,
    this.lastPlayerSubtitleLanguage,
    this.lastPlayerSubtitleTitle,
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
    bool? showSkipIntroButton,
    String? opensubtitlesApiKey,
    String? geminiApiKey,
    bool clearGeminiApiKey = false,
    String? subtitlePreferredLanguage,
    int? subtitleFontSize,
    String? subtitleColor,
    bool? subtitleBold,
    bool? subtitleBackgroundEnabled,
    String? lastPlayerAudioLanguage,
    String? lastPlayerAudioTitle,
    String? lastPlayerSubtitleLanguage,
    String? lastPlayerSubtitleTitle,
    bool clearLastPlayerSubtitleLanguage = false,
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
      showSkipIntroButton: showSkipIntroButton ?? this.showSkipIntroButton,
      opensubtitlesApiKey: opensubtitlesApiKey ?? this.opensubtitlesApiKey,
      geminiApiKey: clearGeminiApiKey
          ? null
          : (geminiApiKey ?? this.geminiApiKey),
      subtitlePreferredLanguage: subtitlePreferredLanguage ?? this.subtitlePreferredLanguage,
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      subtitleBold: subtitleBold ?? this.subtitleBold,
      subtitleBackgroundEnabled: subtitleBackgroundEnabled ?? this.subtitleBackgroundEnabled,
      lastPlayerAudioLanguage: lastPlayerAudioLanguage ?? this.lastPlayerAudioLanguage,
      lastPlayerAudioTitle: lastPlayerAudioTitle ?? this.lastPlayerAudioTitle,
      lastPlayerSubtitleLanguage: clearLastPlayerSubtitleLanguage
          ? null
          : (lastPlayerSubtitleLanguage ?? this.lastPlayerSubtitleLanguage),
      lastPlayerSubtitleTitle: clearLastPlayerSubtitleLanguage
          ? null
          : (lastPlayerSubtitleTitle ?? this.lastPlayerSubtitleTitle),
      defaultAccountId: defaultAccountId ?? this.defaultAccountId,
    );
  }

  /// True when the user has a non-empty Gemini API key on file.
  ///
  /// AI features (natural-language search, the "what should I watch?"
  /// chat sheet, spoiler-free recaps, AI plot summary/translation,
  /// smart subtitle translation) gate themselves on this getter.
  /// When `false`, the corresponding UI entries hide rather than
  /// showing a disabled state — there's no per-feature "you can do
  /// this if you add a key" nag.
  bool get hasAiKey =>
      geminiApiKey != null && geminiApiKey!.trim().isNotEmpty;
}
