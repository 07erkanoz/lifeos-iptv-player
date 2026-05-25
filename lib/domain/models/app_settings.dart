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

  // Skip-Intro UX. When true the player surfaces a "Skip Intro"
  // floating button on series episodes. Falls back to a default
  // [introSkipDefaultSeconds] window when no precise marker has been
  // recorded for the series, so the button always works without
  // requiring per-series setup. When the user marks a precise range
  // through the bookmark dialog, that range overrides the default.
  final bool showSkipIntroButton;

  /// How many seconds of an unmarked series episode count as "intro".
  /// The Skip-Intro button is shown for the first
  /// [introSkipDefaultSeconds] of any series episode that doesn't
  /// have a precise marker. 90 seconds matches the Netflix /
  /// HBO Max / Disney+ default and covers the vast majority of
  /// real-world series intros.
  final int introSkipDefaultSeconds;

  // Floating YouTube trailer PiP on the desktop/TV detail page.
  // Default on — most users like it. Power users / slow connections
  // can switch it off so the detail panel stays static and no
  // background extraction runs.
  final bool showTrailer;

  // Taste-wizard one-shot onboarding. Flipped to true after the
  // wizard finishes (whether the user picked items or dismissed).
  // The dashboard checks this on startup and shows the wizard at
  // most once — re-runnable from Settings → "Beğeni profilini
  // sıfırla".
  final bool tasteWizardCompleted;

  // Timestamp of the last time the user dismissed the weekly
  // digest banner. Null = never seen. The digest provider rate-
  // limits itself to once-per-week using this field.
  final DateTime? lastDigestDismissedAt;

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

  /// Mobile-only fullscreen toggle. When true, the app hides the
  /// system status bar (top clock / battery / signal strip) so the
  /// dashboard / movies / series feels edge-to-edge. The bottom
  /// gesture / nav bar stays visible because hiding it would require
  /// users to swipe up just to back out — too aggressive for a
  /// general-purpose toggle.
  ///
  /// No-op on desktop / TV (those have no Android status bar to
  /// hide). Wired in main.dart's settings listener which calls
  /// SystemChrome.setEnabledSystemUIMode on every settings change.
  final bool fullscreenMode;

  /// Mobile-only opt-in: autoplay the muted hero trailer on the
  /// dashboard hero billboard on Android phones. Default off because
  /// each trailer rotation extracts a YouTube stream and decodes
  /// video in the background — wasteful on metered data and warm on
  /// the phone. Users who like the desktop billboard vibe can flip
  /// this on. No-op on desktop / TV (they always show the hero
  /// trailer when [showTrailer] is true; this flag is only consulted
  /// on the mobile branch of [_HeroBannerState._scheduleTrailer]).
  final bool heroTrailerOnMobile;

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
    this.introSkipDefaultSeconds = 90,
    this.showTrailer = true,
    this.tasteWizardCompleted = false,
    this.lastDigestDismissedAt,
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
    this.fullscreenMode = false,
    this.heroTrailerOnMobile = false,
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
    int? introSkipDefaultSeconds,
    bool? showTrailer,
    bool? tasteWizardCompleted,
    DateTime? lastDigestDismissedAt,
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
    bool? fullscreenMode,
    bool? heroTrailerOnMobile,
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
      introSkipDefaultSeconds:
          introSkipDefaultSeconds ?? this.introSkipDefaultSeconds,
      showTrailer: showTrailer ?? this.showTrailer,
      tasteWizardCompleted:
          tasteWizardCompleted ?? this.tasteWizardCompleted,
      lastDigestDismissedAt:
          lastDigestDismissedAt ?? this.lastDigestDismissedAt,
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
      fullscreenMode: fullscreenMode ?? this.fullscreenMode,
      heroTrailerOnMobile:
          heroTrailerOnMobile ?? this.heroTrailerOnMobile,
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
