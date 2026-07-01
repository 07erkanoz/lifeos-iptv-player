import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/intro_marker_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/core/system_ui.dart';
import 'package:lifeostv/core/playback_signal.dart';
import 'package:lifeostv/core/perf/frosted.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
import 'package:lifeostv/presentation/widgets/player/channel_list_overlay.dart';
import 'package:lifeostv/presentation/widgets/content/program_guide.dart';
import 'package:lifeostv/presentation/widgets/player/epg_overlay.dart';
import 'package:lifeostv/presentation/widgets/player/subtitle_search_overlay.dart';
import 'package:lifeostv/data/services/opensubtitles_service.dart';
import 'package:lifeostv/data/services/subtitle_track_matcher.dart';
import 'package:lifeostv/presentation/widgets/player/subtitle_appearance_controls.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/utils/gpu_detector.dart';
import 'package:lifeostv/utils/mpv_config.dart';
import 'package:lifeostv/data/services/cast_service.dart';
import 'package:lifeostv/data/services/dlna_service.dart';
import 'package:lifeostv/presentation/widgets/player/cast_button.dart';

// ---------------------------------------------------------------------------
//  VideoType
// ---------------------------------------------------------------------------

enum VideoType { live, movie, series }

// ---------------------------------------------------------------------------
//  VideoPlayerScreen
// ---------------------------------------------------------------------------

/// Lightweight channel data for channel switching in player
class PlayerChannel {
  final int streamId;
  final String name;
  final String url;
  final String? logo;
  final String? categoryId;
  final String? categoryName;
  const PlayerChannel({
    required this.streamId,
    required this.name,
    required this.url,
    this.logo,
    this.categoryId,
    this.categoryName,
  });
}

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String title;
  final VideoType type;
  final String? logo;
  final String? category;
  final String? currentProgramTitle;
  final DateTime? programStart;
  final DateTime? programEnd;
  final String? nextEpisodeTitle;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPrevEpisode;
  final String? plot;
  final String? genre;
  final String? year;
  final String? director;
  final String? cast;
  final double? rating;
  final Duration? startPosition;

  /// For series: the parent series channel streamId (so history grid works)
  final int? parentStreamId;

  /// Default intro length (seconds) used when no precise marker has
  /// been recorded for this series. Wired in by the router from
  /// AppSettings; 90 s if unset.
  final int introDefaultSeconds;

  /// Channel list for live TV channel switching (D-pad up/down)
  final List<PlayerChannel>? channels;
  final int? currentChannelIndex;

  /// Category ID → Name map for channel list overlay
  final Map<String, String>? categoryNames;

  const VideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.type = VideoType.live,
    this.logo,
    this.category,
    this.currentProgramTitle,
    this.programStart,
    this.programEnd,
    this.nextEpisodeTitle,
    this.onNextEpisode,
    this.onPrevEpisode,
    this.plot,
    this.genre,
    this.year,
    this.director,
    this.cast,
    this.rating,
    this.startPosition,
    this.parentStreamId,
    this.introDefaultSeconds = 90,
    this.channels,
    this.currentChannelIndex,
    this.categoryNames,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // -- Player ---------------------------------------------------------------
  late final Player _player;
  late final VideoController _controller;

  // -- UI state -------------------------------------------------------------
  bool _showControls = true;
  bool _isPaused = false;
  bool _isBuffering = true;

  // -- Timers ---------------------------------------------------------------
  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _saveProgressTimer;
  // Ensures we persist progress (episode AND parent-series row) a few
  // seconds into playback, instead of waiting for the 20s timer / a
  // clean dispose. Without this an interrupted watch never lands in
  // "Continue watching" — the cause of episodes not showing there.
  bool _savedInitialProgress = false;
  Timer? _posUpdateTimer; // Throttled UI updates for position

  // -- D-pad accumulated seek ----------------------------------------------
  // TV remote seeking: each left/right press shifts a PREVIEW position
  // instantly (progress bar only) and we commit ONE real player.seek()
  // ~400ms after the last press. Without this, every press is a real
  // seek → demuxer flush + keyframe re-decode (a 1-2s stall on HQ/IPTV),
  // so a few quick taps stutter and overshoot. null = no active session.
  Duration? _seekPreview;
  Timer? _seekCommitTimer;

  // -- Position / Duration --------------------------------------------------
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  Duration _rawPos = Duration.zero; // Latest position (no rebuild)
  double _liveProgress = 0.0;

  // -- Volume ---------------------------------------------------------------
  double _volume = 100;

  // -- Next Episode ---------------------------------------------------------
  bool _showNextOverlay = false;
  bool _nextTriggered = false;
  int _nextCountdown = 15;
  Timer? _nextTimer;

  // -- Animations -----------------------------------------------------------
  late final AnimationController _controlsAnim;
  late final Animation<double> _controlsFade;

  // -- Focus ----------------------------------------------------------------
  final _focusNode = FocusNode();

  // -- Stream subscriptions -------------------------------------------------
  final List<StreamSubscription> _subs = [];

  // -- PiP native event subscription (Android only) -------------------------
  StreamSubscription? _pipEventSub;

  // Guards so we only auto-apply remembered audio/subtitle track once per open.
  bool _autoTrackApplied = false;

  // -- Channel switching (live TV only) ------------------------------------
  late int _channelIndex;
  late String _currentTitle;
  late String? _currentLogo;
  bool _showChannelInfo = false;
  Timer? _channelInfoTimer;

  bool _pipTransitioning = false;
  late String _currentUrl;

  // EPG data for channel info overlay
  Program? _currentProgram;
  Program? _nextProgram;
  StreamSubscription? _epgSub;

  // -- Pause badge (VOD only, shows after 2s delay like Tauri) ---------------
  bool _showPauseBadge = false;
  Timer? _pauseBadgeTimer;

  // -- Channel list overlay (live TV) ----------------------------------------
  bool _showChannelList = false;

  // -- EPG guide overlay (live TV) -------------------------------------------
  bool _showEpgGuide = false;

  // -- OpenSubtitles search overlay (VOD only) --------------------------------
  bool _showSubtitleSearch = false;

  // -- Buffering timeout -------------------------------------------------------
  Timer? _bufferingTimeoutTimer;
  bool _showBufferingError = false;

  // -- Fullscreen (desktop only) ---------------------------------------------
  bool _isFullscreen = false;

  // -- Sleep timer ------------------------------------------------------------
  // null = off, "eoe" = stop at end of episode, else a DateTime deadline.
  DateTime? _sleepDeadline;
  bool _sleepAtEpisodeEnd = false;
  Timer? _sleepTimer;

  // -- Gesture / brightness (mobile) -----------------------------------------
  double? _initialBrightness;
  double _gestureBrightness = 0.5;
  double _gestureVolume = 100;
  String? _gestureHudText;
  IconData? _gestureHudIcon;
  double? _gestureHudValue; // 0..1 for progress bar
  Timer? _gestureHudTimer;

  /// Imperative handle to the media_kit Video widget so we can call
  /// `setSubtitleViewPadding(...)` and `update(subtitleViewConfiguration:
  /// ...)` directly. We need this because media_kit_video 2.0.1's
  /// SubtitleViewState captures `padding` into local state in its
  /// initializer (`late EdgeInsets padding = widget.configuration.padding`)
  /// and never re-reads it on widget update — declarative prop changes
  /// silently don't propagate. Style props (font size / color / bold /
  /// background) do read from `widget.configuration` in build, but
  /// because pushes through the notifier are post-frame-deferred we
  /// add an explicit `.update()` call too as a belt-and-braces fix for
  /// "settings'teki alt yazı ayarları değişmiyor".
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  // Per-session subtitle vertical offset — bottom padding in logical pixels
  // inside the SubtitleView. 0 = sitting on the video bottom, larger = higher.
  double _subtitleYOffset = 24;

  // Series intro skip (only set for VideoType.series with a parentStreamId).
  //
  // The marker is sourced from Drift (`introMarkers` table, keyed by parent
  // series id), with a one-shot migration of the legacy
  // `series_intro_<sid>` SharedPreferences key on first read.
  //
  // Visibility window: `pos` falls between `_introStartMs` and
  // `_introEndMs`. If only the legacy single-int key existed, that's
  // mapped to `(0, stored*1000)` so existing users keep their behaviour.
  bool _showSkipIntro = false;
  int? _introStartMs;
  int? _introEndMs;
  StreamSubscription<IntroMarker?>? _introMarkerSub;

  // -- Always on top (desktop only) -------------------------------------------
  bool _isAlwaysOnTop = false;

  // =========================================================================
  //  Lifecycle
  // =========================================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Hide status bar & navigation bar on mobile (immersive mode)
    if (isMobilePlatform) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    // Keep the screen awake while the player is on — so users don't have
    // to tap every few minutes just to keep watching.
    WakelockPlus.enable();

    // Signal the app root to pause main-isolate background work
    // (enrichment / embeddings / LAN sync / EPG) while we play, so
    // their Drift batch writes don't jank the video every ~45 s.
    playbackActiveNotifier.value = true;

    // Remember initial brightness so we can restore it on dispose.
    if (Platform.isAndroid || Platform.isIOS) {
      _captureInitialBrightness();
    }

    // Load a previously remembered intro duration for this series.
    if (widget.type == VideoType.series && widget.parentStreamId != null) {
      _loadIntroDuration();
    }

    // Initialize channel switching state
    _channelIndex = widget.currentChannelIndex ?? 0;
    _currentTitle = widget.title;
    _currentLogo = widget.logo;
    _currentUrl = widget.streamUrl;

    // Start EPG subscription for live TV
    if (widget.type == VideoType.live) {
      final channels = widget.channels;
      if (channels != null && _channelIndex < channels.length) {
        _updateEpgForChannel(channels[_channelIndex].streamId);
      }
    }

    // Check initial fullscreen state (desktop only)
    _checkFullscreenState();

    _controlsAnim = AnimationController(
      vsync: this,
      // Snap controls in/out on TV — no fade composite over the video.
      duration: PlatformHelper.anim(const Duration(milliseconds: 250)),
    );
    _controlsFade = CurvedAnimation(
      parent: _controlsAnim,
      curve: Curves.easeOut,
    );
    _controlsAnim.value = 1.0;

    _initPlayer();

    if (widget.type == VideoType.live) {
      _startLiveProgress();
      // Save a history entry for live TV (so history grid works)
      _saveLiveHistory();
    } else {
      // 20s (was 10s) — halves the main-isolate Drift writes during
      // playback; resume accuracy within 20s is plenty. A final save
      // also runs on dispose.
      _saveProgressTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _saveProgress(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Stop audio when the app leaves the foreground unless we're in
    // Picture-in-Picture (where continued playback is the whole point).
    // Without this, media_kit keeps decoding in the background and the
    // user hears the video after pressing home / switching apps.
    // Mobile only — on desktop a minimised / unfocused window
    // shouldn't stop audio (the user may be listening while working).
    if (!isMobilePlatform) return;
    if (_isInPipMode || _pipTransitioning) return;
    // Only true background states — NOT `inactive`, which also fires
    // for transient things (notification shade, permission dialog) and
    // for the PiP-entry transition, where pausing would defeat PiP.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      try {
        _player.pause();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ── Tear the player down FIRST, unconditionally ──
    // Everything below (progress save, system-UI restore, timer/sub
    // cancellation) is best-effort cleanup. If any of it threw or
    // hung BEFORE we reached the player teardown, the libmpv decoder
    // kept running — that's the "audio keeps playing after back" and
    // "two videos on replay" bug. Stopping + disposing the player at
    // the very top guarantees it never survives this screen.
    try {
      _player.pause();
      _player.stop();
      _player.dispose();
    } catch (_) {}
    _setPlayerActive(false);

    _saveProgress();
    // Restore the APP-level system UI mode on mobile. The player used
    // immersiveSticky while video was on screen; on the way out we must
    // honour the user's fullscreen toggle rather than unconditionally
    // forcing edgeToEdge — otherwise watching anything silently wiped
    // the fullscreen preference and the status bar came back.
    if (isMobilePlatform) {
      applyMobileSystemUiMode(
        fullscreen: ref.read(settingsProvider).fullscreenMode,
      );
    }
    // Restore window from fullscreen and always-on-top when leaving player.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (_isFullscreen) windowManager.setFullScreen(false);
      if (_isAlwaysOnTop) windowManager.setAlwaysOnTop(false);
    }
    for (final s in _subs) {
      s.cancel();
    }
    _epgSub?.cancel();
    _pipEventSub?.cancel();
    _pipEventSub = null;
    _introMarkerSub?.cancel();
    _posUpdateTimer?.cancel();
    _seekCommitTimer?.cancel();
    _channelInfoTimer?.cancel();
    // Player teardown already happened at the top of dispose().
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgressTimer?.cancel();
    _nextTimer?.cancel();
    _pauseBadgeTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    _controlsAnim.dispose();
    _focusNode.dispose();
    _playPauseFocusNode.dispose();
    _sleepTimer?.cancel();
    _gestureHudTimer?.cancel();
    WakelockPlus.disable();
    // Resume background work now that playback is over.
    playbackActiveNotifier.value = false;
    if ((Platform.isAndroid || Platform.isIOS) && _initialBrightness != null) {
      // Fire and forget — don't block dispose.
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
        (_) => null,
      );
    }
    super.dispose();
  }

  /// Subscribe to this series' intro marker from Drift and, on first
  /// run, migrate any legacy `series_intro_<sid>` SharedPreferences
  /// key into the new table so users who already taught the v0
  /// implementation don't lose their setting.
  Future<void> _loadIntroDuration() async {
    final sid = widget.parentStreamId;
    if (sid == null) {
      debugPrint('[intro] no parentStreamId, skipping');
      return;
    }
    debugPrint('[intro] loading marker for seriesId=$sid');

    // One-shot migration: read the legacy single-int "intro length in
    // seconds" key, write it back as a `(0, stored*1000)` range, then
    // delete the legacy key so the migration only happens once.
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyKey = 'series_intro_$sid';
      final legacy = prefs.getInt(legacyKey);
      if (legacy != null && legacy > 0) {
        debugPrint('[intro] migrating legacy key=$legacyKey value=${legacy}s');
        await ref.read(introMarkerRepositoryProvider).setMarker(
              sid,
              introStartMs: 0,
              introEndMs: legacy * 1000,
            );
        await prefs.remove(legacyKey);
      }
    } catch (e) {
      debugPrint('[intro] legacy migration failed: $e');
    }

    // Eager initial read so the position listener has values to compare
    // against from the first frame — relying on `watchSingleOrNull`'s
    // initial emission was racing the player's first position events
    // on devices where Drift's stream wakes a tick later than the
    // media_kit player.
    try {
      final initial = await ref
          .read(introMarkerRepositoryProvider)
          .getMarker(sid);
      if (initial != null && mounted) {
        debugPrint('[intro] initial marker loaded: '
            'start=${initial.introStartMs} end=${initial.introEndMs}');
        setState(() {
          _introStartMs = initial.introStartMs;
          _introEndMs = initial.introEndMs;
        });
      } else {
        debugPrint('[intro] no marker in DB for seriesId=$sid');
      }
    } catch (e) {
      debugPrint('[intro] initial getMarker failed: $e');
    }

    // Live subscription to the marker. The marking UI writes to the
    // same table, so this picks up edits without an extra reload.
    _introMarkerSub = ref
        .read(introMarkerRepositoryProvider)
        .watchMarker(sid)
        .listen((m) {
      if (!mounted) return;
      debugPrint('[intro] marker stream emitted: '
          'start=${m?.introStartMs} end=${m?.introEndMs}');
      setState(() {
        _introStartMs = m?.introStartMs;
        _introEndMs = m?.introEndMs;
      });
    });
  }

  /// Skip past the intro:
  ///   * If the user has marked a precise range, seek to
  ///     `introEndMs`.
  ///   * Otherwise (default-window mode) seek to
  ///     `introDefaultSeconds * 1000` ms — the same target the
  ///     visibility window uses, so tapping while the button is
  ///     showing always lands past the configured intro length.
  Future<void> _skipIntroNow() async {
    final target = _introEndMs ?? widget.introDefaultSeconds * 1000;
    _player.seek(Duration(milliseconds: target));
    setState(() => _showSkipIntro = false);
  }

  /// Two-step marking flow:
  /// 1. User taps "İntro burada başlıyor" while the intro starts on
  ///    screen → we capture the *current* playback position as
  ///    `introStartMs` (kept locally, nothing saved yet).
  /// 2. User taps "İntro burada bitiyor" when the intro ends → we
  ///    capture that as `introEndMs`, validate `end > start`, and
  ///    persist via the repository. The active subscription picks
  ///    the new row up automatically so the Skip button works on
  ///    the next episode (or even right after marking the same
  ///    episode, if it loops).
  ///
  /// Also exposes "Mevcut işareti temizle" when a marker exists, so
  /// users who mis-marked can start over without leaving the player.
  Future<void> _showIntroMarkerDialog() async {
    final sid = widget.parentStreamId;
    if (sid == null) return;
    final l10n = AppLocalizations.of(context)!;
    final repo = ref.read(introMarkerRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    // Capture an *initial* snapshot of the pending start. The dialog
    // is stateful (StatefulBuilder) so the user can tap "Başla" then
    // "Bitti" without the dialog rebuilding from outside.
    int? pendingStartMs;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final hasMarker = _introStartMs != null && _introEndMs != null;
          return Dialog(
            backgroundColor: AppColors.surfaceElevatedDark,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 360,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bookmark_outline,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          l10n.skipIntro,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (hasMarker)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${_fmt(Duration(milliseconds: _introStartMs!))} '
                          '— '
                          '${_fmt(Duration(milliseconds: _introEndMs!))}',
                          style: const TextStyle(
                            color: AppColors.textSecondaryDark,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (pendingStartMs != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${l10n.markIntroStart}: '
                          '${_fmt(Duration(milliseconds: pendingStartMs!))}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    _FocusableTrackTile(
                      title: l10n.markIntroStart,
                      isSelected: pendingStartMs != null,
                      autofocus: pendingStartMs == null,
                      onTap: () {
                        setLocal(() {
                          pendingStartMs = _rawPos.inMilliseconds;
                        });
                      },
                    ),
                    _FocusableTrackTile(
                      title: l10n.markIntroEnd,
                      isSelected: false,
                      autofocus: false,
                      onTap: () async {
                        final start = pendingStartMs;
                        final end = _rawPos.inMilliseconds;
                        debugPrint('[intro] marking dialog: '
                            'start=$start end=$end sid=$sid');
                        if (start == null || end <= start) {
                          debugPrint(
                              '[intro] invalid range, refusing setMarker');
                          messenger.showSnackBar(SnackBar(
                            content: Text(l10n.introMarkInvalid),
                            duration: const Duration(seconds: 2),
                          ));
                          return;
                        }
                        try {
                          await repo.setMarker(
                            sid,
                            introStartMs: start,
                            introEndMs: end,
                          );
                          debugPrint('[intro] setMarker succeeded');
                        } catch (e) {
                          debugPrint('[intro] setMarker failed: $e');
                          if (!ctx.mounted) return;
                          messenger.showSnackBar(SnackBar(
                            content: Text('${l10n.introMarkInvalid}: $e'),
                            duration: const Duration(seconds: 3),
                          ));
                          return;
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        messenger.showSnackBar(SnackBar(
                          content: Text(l10n.introMarked),
                          duration: const Duration(seconds: 2),
                        ));
                      },
                    ),
                    if (hasMarker)
                      _FocusableTrackTile(
                        title: l10n.introCleared,
                        isSelected: false,
                        autofocus: false,
                        onTap: () async {
                          await repo.clearMarker(sid);
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          messenger.showSnackBar(SnackBar(
                            content: Text(l10n.introCleared),
                            duration: const Duration(seconds: 2),
                          ));
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkipIntroButton() {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _skipIntroNow,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.skip_next, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                // Use the precise marker's end if the user recorded
                // one for this series; otherwise the default-window
                // target. The label always reads "Skip Intro
                // (→m:ss)" so the user knows where playback lands.
                '${l10n.skipIntroLabel} (→${_fmt(Duration(milliseconds: _introEndMs ?? widget.introDefaultSeconds * 1000))})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureInitialBrightness() async {
    try {
      final b = await ScreenBrightness.instance.application;
      if (!mounted) return;
      _initialBrightness = b;
      _gestureBrightness = b;
    } catch (_) {}
  }

  // =========================================================================
  //  Subtitle styling helper
  // =========================================================================

  /// Parse a `#RRGGBB` (or `#AARRGGBB`) string into a [Color]. Defaults
  /// to opaque white on any malformed input so a corrupted
  /// `settings.subtitleColor` (manually edited prefs, a migration
  /// glitch, or a future setting we don't know how to parse) doesn't
  /// crash the player.
  Color _hexToColor(String hex) {
    try {
      var h = hex.replaceFirst('#', '');
      if (h.length == 6) h = 'FF$h';
      if (h.length != 8) return const Color(0xFFFFFFFF);
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFFFFFFFF);
    }
  }

  /// Approximate vertical room the player's bottom control bar takes
  /// once visible. Used to lift subtitles above the bar so dialogue
  /// doesn't sit under the progress slider / button row whenever the
  /// controls fade in.
  static const double _controlsLift = 96.0;

  /// Effective bottom padding for the subtitle view: the user-chosen
  /// position offset (`_subtitleYOffset`) plus a temporary lift while
  /// controls are visible.
  double get _effectiveSubtitleBottomPadding =>
      _subtitleYOffset + (_showControls ? _controlsLift : 0);

  /// Cached subtitle config so the Video widget receives a STABLE
  /// object across rebuilds. Rebuilding it on every setState (position
  /// tick, buffering, pause) allocated a TextStyle + Shadows + config
  /// each frame AND made media_kit re-apply the subtitle layout — pure
  /// waste during playback. Recomputed only when subtitle settings
  /// change (via [_applySubtitleStyle]).
  SubtitleViewConfiguration? _subtitleConfig;

  SubtitleViewConfiguration get _cachedSubtitleConfig =>
      _subtitleConfig ??= _buildSubtitleViewConfig();

  SubtitleViewConfiguration _buildSubtitleViewConfig() {
    final s = ref.read(settingsProvider);
    // Map user's settings.subtitleFontSize (20-110, mpv-like scale where
    // ~55 is the libmpv default) into Flutter logical pixels. 55 → 32 matches
    // media_kit's default TextStyle fontSize.
    final flutterSize = (s.subtitleFontSize * 32.0 / 55.0).clamp(12.0, 80.0);
    final fg = _hexToColor(s.subtitleColor);
    return SubtitleViewConfiguration(
      style: TextStyle(
        height: 1.4,
        fontSize: flutterSize,
        color: fg,
        fontWeight: s.subtitleBold ? FontWeight.w700 : FontWeight.w400,
        backgroundColor: s.subtitleBackgroundEnabled
            ? const Color(0xAA000000)
            : const Color(0x00000000),
        shadows: s.subtitleBackgroundEnabled
            ? const []
            : const [
                Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
                Shadow(color: Colors.black, blurRadius: 6),
              ],
      ),
      textAlign: TextAlign.center,
      padding: EdgeInsets.fromLTRB(16, 0, 16, _effectiveSubtitleBottomPadding),
    );
  }

  /// Force the media_kit SubtitleView to pick up the latest style +
  /// padding. We need this because the SubtitleView caches `padding`
  /// in state at initState and never re-reads it on widget update —
  /// declarative prop changes silently no-op for padding. Style props
  /// DO update through the declarative path, but pushing them through
  /// the imperative API too costs nothing and is one bug class fewer.
  Future<void> _applySubtitleStyle() async {
    if (!mounted) return;
    _subtitleConfig = _buildSubtitleViewConfig(); // refresh the cache
    setState(() {});
    final state = _videoKey.currentState;
    if (state != null) {
      state.update(subtitleViewConfiguration: _subtitleConfig);
      state.setSubtitleViewPadding(
        EdgeInsets.fromLTRB(16, 0, 16, _effectiveSubtitleBottomPadding),
        duration: const Duration(milliseconds: 120),
      );
    }
  }

  /// Lighter variant of [_applySubtitleStyle] that only pushes the
  /// padding — used by the controls-show/hide animation where the
  /// rest of the config didn't change. Avoids work and avoids the
  /// `update()` post-frame defer.
  void _pushSubtitlePadding() {
    if (!mounted) return;
    _videoKey.currentState?.setSubtitleViewPadding(
      EdgeInsets.fromLTRB(16, 0, 16, _effectiveSubtitleBottomPadding),
      duration: const Duration(milliseconds: 180),
    );
  }

  // =========================================================================
  //  Player init
  // =========================================================================

  Future<void> _initPlayer() async {
    final settings = ref.read(settingsProvider);

    // Platform-specific video output config
    // Linux: do NOT set vo — media_kit handles rendering via its own OpenGL render context.
    // Setting vo=gpu conflicts with media_kit's texture-based pipeline.
    String? vo;
    if (Platform.isWindows) {
      vo = settings.hardwareAcceleration ? 'gpu' : null;
    }
    // Linux: vo=null lets media_kit control the render pipeline

    _player = Player(
      configuration: PlayerConfiguration(
        vo: vo,
        // 16 MB on Linux (was 8 MB — too small for high-bitrate 1080p,
        // causing periodic rebuffer stutter); 32 MB elsewhere.
        bufferSize: Platform.isLinux ? 16 * 1024 * 1024 : 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      // Honour the "Donanım hızlandırma" setting on EVERY platform,
      // Android TV included. It defaults ON (HW), but must remain a real
      // escape hatch on TV too: some boxes' HW decoders can't play certain
      // streams, and forcing HW there left the toggle dead — the user
      // couldn't fall back to software even when HW produced no video.
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: settings.hardwareAcceleration,
        // Cap the render texture to 720p on Android TV. media_kit copies +
        // GL-renders every frame into a Flutter texture (unlike ExoPlayer's
        // zero-copy SurfaceView); on a weak TV GPU that per-frame cost is
        // the stutter. A 720p texture roughly halves that work — the TV
        // panel upscales to its native resolution. Smoothness over a little
        // sharpness on hardware that otherwise can't keep up.
        width: PlatformHelper.isTV ? 1280 : null,
        height: PlatformHelper.isTV ? 720 : null,
      ),
    );

    // ── mpv performance options (auto-configured per GPU) ──
    if (_player.platform is NativePlayer) {
      final mpv = _player.platform! as NativePlayer;
      final gpu = await GpuDetector.detect();
      await MpvConfig.applyOptimal(mpv, gpu);

      // Wire the "Donanım hızlandırma" setting to mpv's decoder.
      // ON (default): keep the vendor-detected hardware decoder
      // (mediacodec / vaapi / nvdec / d3d11va) with mpv's own safe
      // fallback. OFF: force pure software decoding — the escape hatch
      // for problematic IPTV streams that green-screen / won't play on
      // hardware (costs CPU/battery but plays almost anything).
      // Force pure software decode when the user disabled HW — on TV too.
      // SW is slow for HD, but it's the last-resort path for streams a
      // given box's MediaCodec refuses to play; leaving it unreachable on
      // TV meant "video oynatılamıyor" with no way out.
      if (!settings.hardwareAcceleration) {
        await mpv.setProperty('hwdec', 'no');
      }

      if (widget.type == VideoType.live) {
        // Live TV: aggressive low-latency
        await mpv.setProperty('profile', 'low-latency');
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('cache-secs', '2');
        await mpv.setProperty('demuxer-max-bytes', '8MiB');
        await mpv.setProperty('demuxer-max-back-bytes', '4MiB');
        await mpv.setProperty('demuxer-readahead-secs', '2');
      } else {
        // VOD — honour the user's "Tampon süresi" (buffer duration)
        // setting. Clamped to a sane range so a bad value can't wedge
        // playback. Higher = smoother on flaky connections, more RAM.
        final bufSecs = settings.bufferDuration.clamp(5, 120);
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('cache-secs', '$bufSecs');
        await mpv.setProperty('demuxer-readahead-secs', '$bufSecs');
        // Bigger demuxer cache so high-bitrate (HQ/4K) VOD has enough
        // read-ahead to ride out network dips without rebuffering.
        await mpv.setProperty('demuxer-max-bytes', '64MiB');
        await mpv.setProperty('demuxer-max-back-bytes', '32MiB');
      }

      // Disable subtitles by default only when we have no remembered choice.
      // If the user previously enabled a subtitle language, _applyRememberedTracks
      // will pick the matching track as soon as the track list arrives.
      if (settings.lastPlayerSubtitleLanguage == null) {
        await mpv.setProperty('sid', 'no');
      }

      // Subtitle appearance from settings
      await _applySubtitleStyle();

      // HLS adaptive bitrate quality setting
      final quality = settings.streamQuality;
      switch (quality) {
        case StreamQuality.auto:
          break;
        case StreamQuality.high:
          await mpv.setProperty('hls-bitrate', 'max');
          break;
        case StreamQuality.medium:
          await mpv.setProperty('hls-bitrate', '3000000');
          break;
        case StreamQuality.low:
          await mpv.setProperty('hls-bitrate', '1000000');
          break;
      }
    }

    // ── Stream listeners ──
    _attachStreamListeners();

    // Android PiP: notify native side player is active + listen for PiP state
    _setPlayerActive(true);
    _listenPipEvents();

    await _player.open(Media(widget.streamUrl));
    // Re-apply subtitle appearance now that media is loaded — mpv resets
    // some of these on file open, and our first apply at init was too early
    // (before the subtitle renderer was wired up).
    await _applySubtitleStyle();
    if (widget.startPosition != null) {
      _seekWhenReady(widget.startPosition!);
    } else if (widget.type != VideoType.live) {
      _checkSavedProgress();
    }
    _resetHideTimer();
  }

  void _attachStreamListeners() {
    // Position: store raw value, DON'T setState on every tick.
    _subs.add(
      _player.stream.position.listen((p) {
        _rawPos = p;
        // Land in "Continue watching" early: once we're a few seconds in
        // with a known duration, persist once (saves both the episode
        // and, for series, the parent-series row the dashboard joins on).
        if (!_savedInitialProgress &&
            _dur.inSeconds >= 10 &&
            p.inSeconds >= 3) {
          _savedInitialProgress = true;
          _saveProgress();
        }
        if (widget.type == VideoType.series &&
            widget.onNextEpisode != null &&
            ref.read(settingsProvider).autoNextEpisode &&
            _dur.inSeconds > 0) {
          final remaining = _dur.inSeconds - p.inSeconds;
          if (remaining <= 45 &&
              remaining > 0 &&
              !_showNextOverlay &&
              !_nextTriggered) {
            _startNextCountdown();
          }
        }
        // ── Skip-intro visibility ──────────────────────────────────
        //
        // Two-tier behaviour (Netflix-style):
        //
        //   1. **Default window** — for ANY series episode, show the
        //      "Skip Intro" button during the first
        //      `introSkipDefaultSeconds` of playback. Works with zero
        //      user setup. Default 90 s matches the cadence of
        //      typical episode openings.
        //
        //   2. **Per-series override** — if the user has used the
        //      bookmark dialog to record a precise range for this
        //      series, that range takes precedence over the default
        //      window. Useful for series with unusually long
        //      ("Game of Thrones") or off-front ("episode 1 has
        //      cold-open before intro") openings.
        //
        // Either way the rail relies only on the in-memory state
        // (`_introStartMs/_introEndMs` populated from Drift +
        // `widget.introDefaultSeconds`), so it doesn't matter if the
        // Drift watch hasn't fired yet — the default window kicks in
        // from the first position event.
        if (widget.type == VideoType.series && widget.parentStreamId != null) {
          final hasMarker = _introStartMs != null && _introEndMs != null;
          final bool shouldShow;
          if (hasMarker) {
            shouldShow = p.inMilliseconds >= _introStartMs! &&
                p.inMilliseconds <= _introEndMs!;
          } else {
            shouldShow = p.inMilliseconds <
                widget.introDefaultSeconds * 1000;
          }
          if (shouldShow != _showSkipIntro && mounted) {
            setState(() => _showSkipIntro = shouldShow);
          }
        }
      }),
    );

    // Throttled position UI update (every 500ms). Only repaint when
    // the controls overlay is actually on screen — it lives inside a
    // FadeTransition that is ALWAYS built (top bar + progress slider +
    // ~12 buttons), so an unconditional setState here was rebuilding
    // that whole tree twice a second even behind a 0-opacity overlay
    // during normal viewing. Idle playback now does zero overlay
    // rebuilds; the position re-syncs the instant controls reappear.
    _posUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      // Don't clobber an in-progress D-pad seek preview with the real
      // (not-yet-sought) position.
      if (_seekPreview != null) return;
      if (!_showControls && !_isPaused) return;
      if (_rawPos != _pos) {
        setState(() => _pos = _rawPos);
      }
    });

    _subs.add(
      _player.stream.duration.listen((d) {
        if (mounted) setState(() => _dur = d);
      }),
    );

    _subs.add(
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        if (!playing) {
          _controlsAnim.forward();
          // Coalesce into a single rebuild instead of two back-to-back.
          setState(() {
            _isPaused = true;
            _showControls = true;
          });
          _pushSubtitlePadding();
          _hideTimer?.cancel();
          // Show pause badge after 2s delay (VOD only, like Tauri)
          if (widget.type != VideoType.live && _dur.inSeconds > 0) {
            _pauseBadgeTimer?.cancel();
            _pauseBadgeTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _isPaused) setState(() => _showPauseBadge = true);
            });
          }
        } else {
          _pauseBadgeTimer?.cancel();
          setState(() {
            _isPaused = false;
            _showPauseBadge = false;
          });
          _resetHideTimer();
        }
      }),
    );

    _subs.add(
      _player.stream.buffering.listen((b) {
        if (mounted) {
          setState(() => _isBuffering = b);
          // Buffering timeout: 20 seconds
          if (b) {
            _bufferingTimeoutTimer?.cancel();
            _bufferingTimeoutTimer = Timer(const Duration(seconds: 20), () {
              if (mounted && _isBuffering) {
                setState(() => _showBufferingError = true);
              }
            });
          } else {
            _bufferingTimeoutTimer?.cancel();
            if (_showBufferingError) {
              setState(() => _showBufferingError = false);
            }
          }
        }
      }),
    );

    _subs.add(
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v);
      }),
    );

    // Auto-apply the audio/subtitle track the user picked in the previous
    // episode. Track lists arrive asynchronously after Media is opened.
    _subs.add(
      _player.stream.tracks.listen((_) {
        if (_autoTrackApplied) return;
        if (widget.type == VideoType.live) return;
        _applyRememberedTracks();
      }),
    );
  }

  /// Match the remembered audio/subtitle language against the current
  /// track list and select the best fit. Called once per opened Media.
  ///
  /// Uses [findBestSubtitleTrack] / [findBestAudioTrack] from
  /// `subtitle_track_matcher.dart` so the matching logic is
  /// symmetric, ISO-aware, and unit-tested in isolation. The previous
  /// inline implementation lost the user's pick across episodes when
  /// the same subtitle was exposed as `language` in one episode and
  /// `title` in the next.
  void _applyRememberedTracks() {
    if (_autoTrackApplied) return;
    final settings = ref.read(settingsProvider);
    final tracks = _player.state.tracks;
    final audios = tracks.audio;
    final subs = tracks.subtitle;
    // Wait until real tracks (not just the synthetic auto/no entries) are known.
    final hasRealAudio = audios.any((t) => t.id != 'auto' && t.id != 'no');
    final hasRealSub = subs.any((t) => t.id != 'auto' && t.id != 'no');
    if (!hasRealAudio && !hasRealSub) return;

    if (hasRealAudio &&
        (settings.lastPlayerAudioLanguage != null ||
            settings.lastPlayerAudioTitle != null)) {
      final candidates = audios.map(_toCandidate).toList(growable: false);
      final match = findBestAudioTrack(
        tracks: candidates,
        wantLanguage: settings.lastPlayerAudioLanguage,
        wantTitle: settings.lastPlayerAudioTitle,
      );
      if (match != null) {
        final track = audios.firstWhere((t) => t.id == match.id);
        if (_player.state.track.audio != track) {
          _player.setAudioTrack(track);
        }
      }
    }

    if (hasRealSub &&
        (settings.lastPlayerSubtitleLanguage != null ||
            settings.lastPlayerSubtitleTitle != null)) {
      final candidates = subs.map(_toCandidate).toList(growable: false);
      final match = findBestSubtitleTrack(
        tracks: candidates,
        wantLanguage: settings.lastPlayerSubtitleLanguage,
        wantTitle: settings.lastPlayerSubtitleTitle,
      );
      if (match != null) {
        final track = subs.firstWhere((t) => t.id == match.id);
        if (_player.state.track.subtitle != track) {
          _player.setSubtitleTrack(track);
          _applySubtitleStyle();
        }
      }
    }

    _autoTrackApplied = true;
  }

  /// Adapt media_kit's track types to the matcher's TrackCandidate
  /// shape. Audio and subtitle tracks share id / language / title
  /// fields, so a single conversion works for both.
  TrackCandidate _toCandidate(dynamic t) => (
        id: t.id as String,
        language: t.language as String?,
        title: t.title as String?,
      );

  void _rememberAudioChoice(AudioTrack t) {
    if (t.id == 'auto' || t.id == 'no') return;
    final lang = t.language ?? '';
    final title = t.title ?? '';
    // Track had no usable identifier on either field — nothing to
    // store. Better than persisting a "" / "" pair that turns into
    // "no preference" and silently strips this user's pick next time.
    if (lang.isEmpty && title.isEmpty) return;
    final notifier = ref.read(settingsProvider.notifier);
    final cur = ref.read(settingsProvider);
    notifier.updateSettings(cur.copyWith(
      lastPlayerAudioLanguage: lang,
      lastPlayerAudioTitle: title,
    ));
  }

  void _rememberSubtitleChoice(SubtitleTrack t) {
    final notifier = ref.read(settingsProvider.notifier);
    final cur = ref.read(settingsProvider);
    // "Off" → clear remembered subtitle so the next episode starts
    // with subtitles off too. clearLastPlayerSubtitleLanguage clears
    // both the language and the title slots.
    if (t.id == 'no') {
      notifier.updateSettings(
        cur.copyWith(clearLastPlayerSubtitleLanguage: true),
      );
      return;
    }
    if (t.id == 'auto') return;
    final lang = t.language ?? '';
    final title = t.title ?? '';
    if (lang.isEmpty && title.isEmpty) return;
    notifier.updateSettings(cur.copyWith(
      lastPlayerSubtitleLanguage: lang,
      lastPlayerSubtitleTitle: title,
    ));
  }

  // =========================================================================
  //  Seek with readiness check
  // =========================================================================

  /// Seek to position, waiting for player to report duration if needed.
  /// This prevents seek failures when the media hasn't loaded yet.
  void _seekWhenReady(Duration target) {
    if (_dur.inSeconds > 0) {
      _player.seek(target);
      return;
    }
    // Player not ready yet — wait for duration to be reported
    late StreamSubscription<Duration> sub;
    sub = _player.stream.duration.listen((d) {
      if (d.inSeconds > 0) {
        sub.cancel();
        if (mounted) _player.seek(target);
      }
    });
    _subs.add(sub);
  }

  // =========================================================================
  //  Progress persistence
  // =========================================================================

  Future<void> _checkSavedProgress() async {
    try {
      final sid = int.tryParse(
        widget.streamUrl.split('/').last.split('.').first,
      );
      if (sid == null) return;
      final p = await ref
          .read(playerRepositoryProvider)
          .getProgress(sid, widget.type.name);
      if (p != null && !p.isFinished && p.position > 1000 && mounted) {
        final l10n = AppLocalizations.of(context)!;
        _showResumeDialog(l10n, Duration(milliseconds: p.position));
      }
    } catch (_) {}
  }

  void _showResumeDialog(AppLocalizations l10n, Duration savedPos) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          l10n.resumePlayback,
          style: const TextStyle(color: AppColors.textDark, fontSize: 17),
        ),
        content: Text(
          '${_fmt(savedPos)} / ${_fmt(_dur)}',
          style: const TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              l10n.no,
              style: const TextStyle(color: AppColors.textSecondaryDark),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _seekWhenReady(savedPos);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.yes),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProgress() async {
    if (_dur.inSeconds < 10) return;
    // Use _rawPos (always current) not _pos (throttled, only refreshed
    // while controls are visible) so an early/auto save records a real
    // position > 0 — otherwise the row is filtered out of the rail.
    final posMs = _rawPos.inMilliseconds;
    if (posMs <= 0) return;
    try {
      final sid = int.tryParse(
        widget.streamUrl.split('/').last.split('.').first,
      );
      if (sid != null) {
        final repo = ref.read(playerRepositoryProvider);
        // Save episode-level progress (for resume)
        await repo.saveProgress(
          sid,
          widget.type.name,
          posMs,
          _dur.inMilliseconds,
        );
        // For series: also save progress for the parent series channel
        // so that watchContinueWatching('series') join works in history grid
        if (widget.type == VideoType.series &&
            widget.parentStreamId != null &&
            widget.parentStreamId != sid) {
          await repo.saveProgress(
            widget.parentStreamId!,
            widget.type.name,
            posMs,
            _dur.inMilliseconds,
          );
        }
      }
    } catch (_) {}
  }

  /// Save a history entry for live TV channel (for the history grid)
  Future<void> _saveLiveHistory() async {
    try {
      final sid = _resolveCurrentLiveStreamId();
      if (sid != null) {
        await ref
            .read(playerRepositoryProvider)
            .saveProgress(
              sid,
              'live',
              1,
              100, // minimal values just to create a record
            );
      }
    } catch (_) {}
  }

  void _startLiveProgress() {
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Guard against the rare window where dispose() runs between
      // the timer firing and the cancel() in dispose taking effect —
      // setState on an unmounted State throws.
      if (!mounted) return;
      // The live progress bar only shows inside the controls overlay,
      // so don't rebuild it every second while controls are hidden.
      if (!_showControls && !_isPaused) return;
      if (widget.programStart != null && widget.programEnd != null) {
        final total = widget.programEnd!
            .difference(widget.programStart!)
            .inSeconds;
        final cur = DateTime.now().difference(widget.programStart!).inSeconds;
        if (total > 0) {
          setState(() => _liveProgress = (cur / total).clamp(0.0, 1.0));
        }
      }
    });
  }

  // =========================================================================
  //  Next episode
  // =========================================================================

  void _startNextCountdown() {
    setState(() {
      _showNextOverlay = true;
      _nextCountdown = 15;
    });
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nextCountdown--);
      if (_nextCountdown <= 0) {
        _nextTimer?.cancel();
        _triggerNext();
      }
    });
  }

  void _triggerNext() {
    if (_nextTriggered) return;
    _nextTriggered = true;
    _nextTimer?.cancel();
    // Sleep timer "stop at end of episode": suppress auto-advance and pause.
    if (_sleepAtEpisodeEnd) {
      _onSleepTimerFired();
      return;
    }
    widget.onNextEpisode?.call();
  }

  void _cancelNext() {
    _nextTimer?.cancel();
    setState(() {
      _showNextOverlay = false;
      _nextTriggered = true;
    });
  }

  // =========================================================================
  //  Channel switching (live TV - just changes URL, no player recreation)
  // =========================================================================

  /// Subscribe to EPG data for a live TV channel
  void _updateEpgForChannel(int streamId) {
    _epgSub?.cancel();
    _epgSub = ref
        .read(contentRepositoryProvider)
        .watchPrograms(streamId)
        .listen((programs) {
          if (!mounted) return;
          final now = DateTime.now();
          Program? current;
          Program? next;
          for (final p in programs) {
            if (p.start.isBefore(now) && p.stop.isAfter(now)) {
              current = p;
            } else if (p.start.isAfter(now) && next == null) {
              next = p;
            }
            if (current != null && next != null) break;
          }
          if (mounted) {
            setState(() {
              _currentProgram = current;
              _nextProgram = next;
            });
          }
        });
  }

  void _switchChannel(int newIndex) {
    final channels = widget.channels;
    if (channels == null || channels.isEmpty) return;
    if (newIndex < 0 || newIndex >= channels.length) return;
    if (newIndex == _channelIndex) return;

    final ch = channels[newIndex];
    setState(() {
      _channelIndex = newIndex;
      _currentTitle = ch.name;
      _currentLogo = ch.logo;
      _isBuffering = true;
      _showChannelInfo = true;
      _currentProgram = null;
      _nextProgram = null;
    });

    // Just open new URL - player instance stays the same (no recreation)
    _currentUrl = ch.url;
    _autoTrackApplied = false;
    _player.open(Media(ch.url));

    // Save history entry for the new channel
    try {
      ref
          .read(playerRepositoryProvider)
          .saveProgress(ch.streamId, 'live', 1, 100);
    } catch (_) {}

    // Update EPG for new channel
    _updateEpgForChannel(ch.streamId);

    // Show channel info overlay for 5 seconds
    _channelInfoTimer?.cancel();
    _channelInfoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showChannelInfo = false);
    });
  }

  void _channelUp() {
    final channels = widget.channels;
    if (channels == null || channels.isEmpty) return;
    final newIdx = (_channelIndex - 1 + channels.length) % channels.length;
    _switchChannel(newIdx);
  }

  void _channelDown() {
    final channels = widget.channels;
    if (channels == null || channels.isEmpty) return;
    final newIdx = (_channelIndex + 1) % channels.length;
    _switchChannel(newIdx);
  }

  int? _resolveCurrentLiveStreamId() {
    final channels = widget.channels;
    if (channels != null &&
        _channelIndex >= 0 &&
        _channelIndex < channels.length) {
      return channels[_channelIndex].streamId;
    }
    return _extractStreamIdFromUrl(widget.streamUrl);
  }

  int? _extractStreamIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : url.split('/').last;
    final normalized = lastSegment.split('?').first;
    final direct = int.tryParse(normalized.split('.').first);
    if (direct != null) return direct;
    final match = RegExp(r'(\d+)(?:\.[A-Za-z0-9]+)?$').firstMatch(normalized);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  // =========================================================================
  //  Controls visibility - SINGLE UNIFIED SYSTEM
  // =========================================================================

  void _toggleControls() {
    if (_isPaused) return; // Always show when paused
    if (_showControls) {
      _controlsAnim.reverse();
      setState(() => _showControls = false);
      _pushSubtitlePadding();
      _reassertImmersive();
      // Reclaim focus from the (now hidden) bottom bar — see _resetHideTimer.
      if (_controlsHaveFocus) _focusNode.requestFocus();
    } else {
      _controlsAnim.forward();
      setState(() => _showControls = true);
      _pushSubtitlePadding();
      _resetHideTimer();
    }
  }

  void _showControlsBriefly() {
    if (!_showControls) {
      _controlsAnim.forward();
      setState(() => _showControls = true);
      _pushSubtitlePadding();
    }
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isPaused) {
        _controlsAnim.reverse();
        setState(() => _showControls = false);
        _pushSubtitlePadding();
        _reassertImmersive();
        // Return focus to the video surface so it isn't stranded
        // (invisible) on a now-hidden bottom-bar button — otherwise the
        // next D-pad press silently seeks / switches channel behind the
        // faded controls instead of revealing them.
        if (_controlsHaveFocus) _focusNode.requestFocus();
      }
    });
  }

  /// Re-apply Android immersive mode. The OS sometimes "leaks" out of
  /// immersiveSticky after seek / swipe / accessibility events and
  /// leaves the status + nav bar visible even though our controls have
  /// already faded. Calling setEnabledSystemUIMode here forces Android
  /// to hide them again in the same frame as our control fade. No-op
  /// on desktop / iOS (iOS handles fullscreen player chrome via
  /// SystemUiOverlayStyle elsewhere).
  void _reassertImmersive() {
    if (!isMobilePlatform) return;
    if (!Platform.isAndroid) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // =========================================================================
  //  Keyboard / remote
  // =========================================================================

  /// Whether bottom bar controls are focused (D-pad navigated to them)
  bool _controlsHaveFocus = false;

  void _onControlsFocusChange(bool hasFocus) {
    _controlsHaveFocus = hasFocus;
  }

  /// Handle key events at the top level (video area).
  /// When controls are showing AND focused, let D-pad navigate between buttons.
  /// When controls are hidden or video area is focused, handle seek/volume.
  /// D-pad seek: shift a preview position by [seconds] instantly and
  /// schedule a single real seek once the user stops pressing. Repeated
  /// taps accumulate against the preview, not against repeated flushes.
  void _nudgeSeek(int seconds) {
    final base = _seekPreview ?? _rawPos;
    var target = base + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_dur > Duration.zero && target > _dur) target = _dur;
    setState(() {
      _seekPreview = target;
      _pos = target; // live progress-bar + time-label preview
    });
    _showControlsBriefly();
    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final t = _seekPreview;
      _seekPreview = null;
      if (t != null) _player.seek(t);
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    // Back / Escape → close overlay first, then exit player
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      // Close overlays in priority order
      if (_showSubtitleSearch) {
        setState(() => _showSubtitleSearch = false);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_showEpgGuide) {
        setState(() => _showEpgGuide = false);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_showChannelList) {
        setState(() => _showChannelList = false);
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      // No overlay open.
      // Desktop fullscreen: ESC exits fullscreen first.
      if (_isFullscreen &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        _setFullscreen(false);
        _showControlsBriefly();
        return KeyEventResult.handled;
      }

      // Platforms with PiP support: ESC shrinks to PiP instead of hard-exit.
      if (k == LogicalKeyboardKey.escape && isDesktopPipSupported) {
        _enterPipMode();
        return KeyEventResult.handled;
      }

      // Otherwise exit player.
      if (mounted) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    // An overlay (channel list / EPG / subtitle search) owns the screen.
    // Its own Focus handles navigation inside it; swallow the nav /
    // activation keys here so a press the overlay declined (an edge press,
    // or a still-unfocusable row) can't leak through to seek /
    // channel-switch / volume / play-pause behind the open overlay.
    // Back/Escape (above) and the C/G/F/I toggles (below) still work.
    if (_showChannelList || _showEpgGuide || _showSubtitleSearch) {
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.mediaPlayPause ||
          k == LogicalKeyboardKey.select ||
          k == LogicalKeyboardKey.enter) {
        return KeyEventResult.handled;
      }
    }

    // Play / Pause (select/enter on video area, or space)
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }

    // Select/enter when controls hidden → play/pause directly (TV: OK
    // button is the natural pause toggle) AND reveal controls so the
    // user can navigate from the now-focused play button.
    if ((k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) &&
        !_showControls) {
      _player.playOrPause();
      _showControlsBriefly();
      _playPauseFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // When bottom bar buttons are focused, let D-pad navigate normally
    if (_controlsHaveFocus && _showControls) {
      // Let the framework handle left/right/up/down for focus traversal
      return KeyEventResult.ignored;
    }

    // Arrow keys when controls are NOT focused → seek/volume
    if (k == LogicalKeyboardKey.arrowLeft) {
      _nudgeSeek(-10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _nudgeSeek(10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      // Live TV: channel up (if channels available)
      if (widget.type == VideoType.live &&
          widget.channels != null &&
          widget.channels!.isNotEmpty) {
        _channelUp();
        return KeyEventResult.handled;
      }
      _player.setVolume(min(_volume + 5, 100));
      _showControlsBriefly();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      // Live TV: channel down (if channels available)
      if (widget.type == VideoType.live &&
          widget.channels != null &&
          widget.channels!.isNotEmpty) {
        _channelDown();
        return KeyEventResult.handled;
      }
      // Show controls and focus the play button
      _showControlsBriefly();
      _playPauseFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Mute toggle
    if (k == LogicalKeyboardKey.keyM) {
      _player.setVolume(_volume > 0 ? 0 : 100);
      return KeyEventResult.handled;
    }

    // Channel list toggle (C key, live TV only)
    if (k == LogicalKeyboardKey.keyC &&
        widget.type == VideoType.live &&
        widget.channels != null &&
        widget.channels!.isNotEmpty) {
      setState(() => _showChannelList = !_showChannelList);
      return KeyEventResult.handled;
    }

    // EPG guide toggle (G key, live TV only)
    if (k == LogicalKeyboardKey.keyG && widget.type == VideoType.live) {
      setState(() => _showEpgGuide = !_showEpgGuide);
      return KeyEventResult.handled;
    }

    // Fullscreen toggle (F key, desktop only)
    if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // Stream stats (I key — like mpv)
    if (k == LogicalKeyboardKey.keyI) {
      _showStreamStatsDialog();
      return KeyEventResult.handled;
    }

    // Any other key → show controls
    _showControlsBriefly();
    return KeyEventResult.ignored;
  }

  // Focus node for the play/pause button (so we can programmatically focus it)
  final _playPauseFocusNode = FocusNode();

  // =========================================================================
  //  Track pickers (audio/subtitle) - as full-screen dialog for D-pad
  // =========================================================================

  /// Open the Xtream timeshift / catch-up stream for [program] on
  /// [channelStreamId]. Called from the EPG overlay when the user
  /// taps a past programme that's still within the provider's
  /// timeshift window.
  ///
  /// Builds the URL via [StreamUrlBuilder.timeshift] and swaps the
  /// current player Media. We deliberately stay on the same route
  /// rather than push a new player — the EPG overlay is a child of
  /// THIS player, so a new push would stack a second media_kit
  /// instance unnecessarily.
  Future<void> _startTimeshift(int channelStreamId, Program program) async {
    final acc = await ref.read(currentAccountProvider.future);
    if (acc == null ||
        acc.username == null ||
        acc.password == null) {
      // M3U accounts don't expose timeshift; surface a brief notice.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.catchupUnavailable)),
      );
      return;
    }
    final duration = program.stop.difference(program.start);
    final url = StreamUrlBuilder.timeshift(
      acc.url,
      acc.username!,
      acc.password!,
      channelStreamId,
      start: program.start,
      duration: duration,
    );
    // Hide the EPG overlay so the user sees the player while
    // the new media loads.
    if (mounted) setState(() => _showEpgGuide = false);
    try {
      await _player.open(Media(url), play: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .timeshiftReplaying(program.title)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[timeshift] open failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.catchupOpenFailed)),
        );
      }
    }
  }

  /// Show a video-quality (bitrate / resolution) picker.
  ///
  /// libmpv exposes alternate video tracks through
  /// `_player.state.tracks.video`. For Xtream IPTV catalogues:
  ///   * VOD endpoints are usually progressive single-bitrate files
  ///     → only `auto` + one real track → we hide the button.
  ///   * Live channels backed by HLS .m3u8 master playlists expose
  ///     one entry per variant stream → we list them all so the
  ///     user can pin a specific resolution / bitrate manually
  ///     (e.g. force 720p on a flaky connection).
  ///
  /// Selecting "Auto" hands control back to libmpv's ABR. Picking
  /// a specific track locks playback to that variant.
  void _showQualityPicker() {
    final l10n = AppLocalizations.of(context)!;
    // Filter out the `no` (none) synthetic — video always has one.
    final tracks = _player.state.tracks.video;
    final real = tracks.where((t) => t.id != 'no').toList();

    if (real.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noOptions),
          backgroundColor: AppColors.surfaceElevatedDark,
        ),
      );
      return;
    }

    // Human-readable label for a video track. media_kit gives us
    // width / height / bitrate when the source manifest provided
    // them — fall back to the bare id when not.
    String labelFor(VideoTrack t) {
      if (t.id == 'auto') return l10n.qualityAuto;
      final w = t.w;
      final h = t.h;
      final bitrate = t.bitrate;
      final parts = <String>[];
      if (h != null) {
        parts.add('${h}p');
      } else if (w != null) {
        parts.add('${w}px');
      }
      if (bitrate != null && bitrate > 0) {
        final kbps = (bitrate / 1000).round();
        parts.add('${kbps}k');
      }
      if (t.title != null && t.title!.isNotEmpty) {
        parts.add(t.title!);
      }
      return parts.isEmpty
          ? (t.language ?? 'Track ${t.id}')
          : parts.join(' · ');
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    const Icon(Icons.high_quality,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(l10n.streamQuality,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        )),
                  ]),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: real.length,
                    itemBuilder: (_, i) {
                      final t = real[i];
                      final selected = _player.state.track.video == t;
                      return _FocusableTrackTile(
                        title: labelFor(t),
                        isSelected: selected,
                        autofocus: selected || i == 0,
                        onTap: () {
                          _player.setVideoTrack(t);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTrackPicker(String type) {
    final l10n = AppLocalizations.of(context)!;
    final isAudio = type == 'audio';
    final tracks = isAudio
        ? _player.state.tracks.audio
        : _player.state.tracks.subtitle;

    // For subtitles, add a "Disabled" option at the top so user can turn them off
    final displayTracks = isAudio
        ? tracks
        : [SubtitleTrack.no(), ...tracks];

    if (displayTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noOptions),
          backgroundColor: AppColors.surfaceElevatedDark,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        isAudio ? Icons.audiotrack : Icons.subtitles,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isAudio ? l10n.audioTrack : l10n.subtitle,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: displayTracks.length,
                    itemBuilder: (_, i) {
                      final t = displayTracks[i];
                      final sel = isAudio
                          ? _player.state.track.audio == t
                          : _player.state.track.subtitle == t;
                      // Label: "Kapalı" for SubtitleTrack.no(), else track info
                      final label = (!isAudio && t.id == 'no')
                          ? l10n.close // "Kapalı" / "Off"
                          : t.title ?? t.language ?? 'Track ${i + 1}';
                      return _FocusableTrackTile(
                        title: label,
                        isSelected: sel,
                        autofocus: sel || i == 0,
                        onTap: () {
                          if (isAudio) {
                            _player.setAudioTrack(t as AudioTrack);
                            _rememberAudioChoice(t);
                          } else {
                            _player.setSubtitleTrack(t as SubtitleTrack);
                            _applySubtitleStyle();
                            _rememberSubtitleChoice(t);
                          }
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
                // Subtitle appearance controls (only in subtitle picker).
                // Full set — size + color + bold + background — via the
                // shared SubtitleAppearanceControls so this stays in
                // sync with Settings. Position lives below since it's
                // player-local state, not in AppSettings.
                if (!isAudio) ...[
                  const Divider(color: Colors.white12, height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SubtitleAppearanceControls(
                          compact: true,
                          // Outer Video widget needs to rebuild so the
                          // fresh SubtitleViewConfiguration reaches it.
                          onChanged: () {
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        StatefulBuilder(
                          builder: (context, setLocal) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.vertical_align_bottom,
                                      color: AppColors.textTertiaryDark,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l10n.subtitlePosition,
                                      style: const TextStyle(
                                        color: AppColors.textSecondaryDark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${_subtitleYOffset.round()}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: _subtitleYOffset,
                                  min: 0,
                                  max: 300,
                                  divisions: 30,
                                  onChanged: (v) {
                                    _subtitleYOffset = v;
                                    setLocal(() {});
                                    if (mounted) setState(() {});
                                    // Push padding through the
                                    // imperative API — declarative
                                    // prop changes are no-ops because
                                    // SubtitleViewState caches padding
                                    // at init.
                                    _pushSubtitlePadding();
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  // Subtitle position/style is no longer pushed into mpv — media_kit renders
  // subtitles with a Flutter widget (see _buildSubtitleViewConfig). The old
  // mpv `sub-pos` / `sub-font-size` path was a dead end because libass wasn't
  // doing the drawing.

  /// Map the persisted fit-mode string to a [BoxFit] for the Video
  /// widget. Unknown values fall back to `contain` (the safe default).
  static BoxFit _boxFitFor(String mode) {
    switch (mode) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      case 'contain':
      default:
        return BoxFit.contain;
    }
  }

  /// Control-bar icon reflecting the current fit mode.
  static IconData _fitIcon(String mode) {
    switch (mode) {
      case 'cover':
        return Icons.crop_free;
      case 'fill':
        return Icons.aspect_ratio;
      case 'contain':
      default:
        return Icons.fit_screen;
    }
  }

  String _fitLabel(String mode) {
    final l10n = AppLocalizations.of(context)!;
    switch (mode) {
      case 'cover':
        return l10n.videoFitCover;
      case 'fill':
        return l10n.videoFitFill;
      case 'contain':
      default:
        return l10n.videoFitContain;
    }
  }

  /// Cycle contain → cover → fill → contain, persist the choice so it
  /// sticks for the next video, and flash the new mode's name.
  void _cycleVideoFit() {
    const order = ['contain', 'cover', 'fill'];
    final cur = ref.read(settingsProvider);
    final idx = order.indexOf(cur.videoFitMode);
    final next = order[(idx + 1) % order.length];
    ref
        .read(settingsProvider.notifier)
        .updateSettings(cur.copyWith(videoFitMode: next));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${AppLocalizations.of(context)!.videoFit}: '
            '${_fitLabel(next)}'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSpeedPicker() {
    final l10n = AppLocalizations.of(context)!;
    final speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speed, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      l10n.playbackSpeed,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: speeds.map((s) {
                    final active = _player.state.rate == s;
                    return _FocusableSpeedChip(
                      speed: s,
                      isActive: active,
                      autofocus: active,
                      onTap: () {
                        _player.setRate(s);
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  //  Helpers
  // =========================================================================

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h == '00' ? '$m:$s' : '$h:$m:$s';
  }

  String _typeBadgeLabel(AppLocalizations l10n) {
    switch (widget.type) {
      case VideoType.live:
        return l10n.live;
      case VideoType.movie:
        return l10n.movie;
      case VideoType.series:
        return l10n.seriesLabel;
    }
  }

  Color _typeBadgeColor() {
    switch (widget.type) {
      case VideoType.live:
        return Colors.red;
      case VideoType.movie:
        return AppColors.primary;
      case VideoType.series:
        return AppColors.accent;
    }
  }

  // =========================================================================
  //  PiP Mode (Desktop + Android)
  // =========================================================================

  static const _platformChannel = MethodChannel(
    'com.lifeostv.lifeostv/platform',
  );
  static const _pipEventChannel = EventChannel(
    'com.lifeostv.lifeostv/pip_events',
  );
  bool _isInPipMode = false;

  void _listenPipEvents() {
    if (!Platform.isAndroid) return;
    _pipEventSub?.cancel();
    _pipEventSub = _pipEventChannel.receiveBroadcastStream().listen((event) {
      if (!mounted) return;
      final inPip = event == true;
      if (inPip != _isInPipMode) {
        setState(() => _isInPipMode = inPip);
        if (!inPip) {
          // Returned from PiP → show controls
          _resetHideTimer();
        }
      }
    });
  }

  /// Notify native side that player is active (enables auto-PiP on home press)
  Future<void> _setPlayerActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _platformChannel.invokeMethod('setPlayerActive', {
        'active': active,
      });
    } catch (_) {}
  }

  // ===========================================================================
  //  Mobile gesture controls (brightness, volume, double-tap seek)
  // ===========================================================================

  bool _gestureStartedOnLeft = true;

  void _handleDoubleTapSeek(Offset globalPos) {
    final size = MediaQuery.of(context).size;
    final isLeft = globalPos.dx < size.width / 2;
    final delta = isLeft ? const Duration(seconds: -10) : const Duration(seconds: 10);
    final target = _rawPos + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_dur > Duration.zero && target > _dur ? _dur : target);
    _player.seek(clamped);
    _showGestureHud(
      isLeft ? Icons.fast_rewind : Icons.fast_forward,
      isLeft ? '-10 sn' : '+10 sn',
      null,
    );
  }

  void _onVerticalDragStart(Offset globalPos) {
    final size = MediaQuery.of(context).size;
    _gestureStartedOnLeft = globalPos.dx < size.width / 2;
    // Seed from the most recent known value so gradual drags feel continuous.
    _gestureVolume = _volume;
  }

  Future<void> _onVerticalDragUpdate(double dyPrimary) async {
    final screenH = MediaQuery.of(context).size.height;
    // Full swipe top-to-bottom = full range. dy > 0 means drag down = decrease.
    final delta = -(dyPrimary / screenH);
    if (_gestureStartedOnLeft) {
      _gestureBrightness = (_gestureBrightness + delta).clamp(0.0, 1.0);
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(
          _gestureBrightness,
        );
      } catch (_) {}
      _showGestureHud(
        _gestureBrightness <= 0.01
            ? Icons.brightness_low
            : (_gestureBrightness >= 0.99
                ? Icons.brightness_high
                : Icons.brightness_6),
        '${(_gestureBrightness * 100).round()}%',
        _gestureBrightness,
      );
    } else {
      _gestureVolume = (_gestureVolume + delta * 100).clamp(0.0, 100.0);
      _player.setVolume(_gestureVolume);
      _showGestureHud(
        _gestureVolume <= 0.5
            ? Icons.volume_off
            : (_gestureVolume >= 99.5 ? Icons.volume_up : Icons.volume_down),
        '${_gestureVolume.round()}%',
        _gestureVolume / 100,
      );
    }
  }

  void _showGestureHud(IconData icon, String text, double? value) {
    if (!mounted) return;
    setState(() {
      _gestureHudIcon = icon;
      _gestureHudText = text;
      _gestureHudValue = value;
    });
    _gestureHudTimer?.cancel();
    _gestureHudTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _gestureHudIcon = null;
        _gestureHudText = null;
        _gestureHudValue = null;
      });
    });
  }

  // ===========================================================================
  //  Sleep timer
  // ===========================================================================

  bool get _isSleepTimerActive => _sleepDeadline != null || _sleepAtEpisodeEnd;

  IconData _sleepTimerIcon() {
    return _isSleepTimerActive ? Icons.bedtime : Icons.bedtime_outlined;
  }

  void _setSleepDuration(Duration d) {
    _sleepTimer?.cancel();
    setState(() {
      _sleepAtEpisodeEnd = false;
      _sleepDeadline = DateTime.now().add(d);
    });
    _sleepTimer = Timer(d, () {
      if (!mounted) return;
      _onSleepTimerFired();
    });
  }

  void _setSleepAtEpisodeEnd() {
    _sleepTimer?.cancel();
    setState(() {
      _sleepAtEpisodeEnd = true;
      _sleepDeadline = null;
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _sleepDeadline = null;
      _sleepAtEpisodeEnd = false;
    });
  }

  void _onSleepTimerFired() {
    _player.pause();
    setState(() {
      _sleepDeadline = null;
      _sleepAtEpisodeEnd = false;
    });
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sleepTimerFired),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSleepTimerPicker() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bedtime, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      l10n.sleepTimer,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final m in const [15, 30, 45, 60])
                  _FocusableTrackTile(
                    title: l10n.minutesShort(m),
                    isSelected:
                        _sleepDeadline != null &&
                        _sleepDeadline!
                                .difference(DateTime.now())
                                .inMinutes ==
                            m - 1 ||
                        (_sleepDeadline != null &&
                            _sleepDeadline!
                                    .difference(DateTime.now())
                                    .inMinutes ==
                                m),
                    autofocus: false,
                    onTap: () {
                      _setSleepDuration(Duration(minutes: m));
                      Navigator.pop(ctx);
                    },
                  ),
                if (widget.type == VideoType.series)
                  _FocusableTrackTile(
                    title: l10n.sleepTimerStopAtEpisodeEnd,
                    isSelected: _sleepAtEpisodeEnd,
                    autofocus: false,
                    onTap: () {
                      _setSleepAtEpisodeEnd();
                      Navigator.pop(ctx);
                    },
                  ),
                if (_isSleepTimerActive)
                  _FocusableTrackTile(
                    title: l10n.sleepTimerCancelAction,
                    isSelected: false,
                    autofocus: false,
                    onTap: () {
                      _cancelSleepTimer();
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  //  Stream stats overlay — codec / resolution / bitrate / dropped frames
  //  Pulled live from libmpv properties; one-shot snapshot dialog (no polling).
  // =========================================================================

  Future<void> _showStreamStatsDialog() async {
    if (_player.platform is! NativePlayer) return;
    final mpv = _player.platform! as NativePlayer;

    Future<String?> get(String prop) async {
      try {
        final v = await mpv.getProperty(prop);
        if (v.toString().isEmpty) return null;
        return v.toString();
      } catch (_) {
        return null;
      }
    }

    final width = await get('width');
    final height = await get('height');
    final vCodec = await get('video-codec');
    final vBitrate = await get('video-bitrate');
    final aCodec = await get('audio-codec');
    final aBitrate = await get('audio-bitrate');
    final fps = await get('estimated-vf-fps');
    final dropped = await get('decoder-frame-drop-count');
    final aChannels = await get('audio-params/channel-count');

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;

    String formatBitrate(String? bps) {
      final n = double.tryParse(bps ?? '');
      if (n == null || n <= 0) return '—';
      if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} Mbps';
      if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)} kbps';
      return '${n.toInt()} bps';
    }

    String formatFps(String? raw) {
      final n = double.tryParse(raw ?? '');
      if (n == null || n <= 0) return '—';
      return '${n.toStringAsFixed(1)} fps';
    }

    final res = (width != null && height != null) ? '$width × $height' : '—';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    l10n.streamStats,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _statRow(l10n.resolution, res),
                _statRow(l10n.videoCodec, vCodec ?? '—'),
                _statRow(l10n.frameRate, formatFps(fps)),
                _statRow(l10n.bitrate, formatBitrate(vBitrate)),
                const Divider(color: Colors.white12, height: 24),
                _statRow(l10n.audioCodec, aCodec ?? '—'),
                _statRow(l10n.audioChannels, aChannels ?? '—'),
                _statRow(l10n.bitrate, formatBitrate(aBitrate)),
                const Divider(color: Colors.white12, height: 24),
                _statRow(l10n.droppedFrames, dropped ?? '0'),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enterPipMode() async {
    if (_pipTransitioning) return;
    _pipTransitioning = true;
    try {
      if (Platform.isAndroid) {
        // Android: use native PiP — player stays alive, just shrinks the window
        _saveProgress();
        try {
          await _platformChannel.invokeMethod('enterPipMode');
        } catch (_) {}
        return;
      }

      if (!isDesktopPipSupported) return;

      _saveProgress();

      // Restore fullscreen/always-on-top before entering PiP (PiP manages its own window state)
      if (_isFullscreen) {
        await windowManager.setFullScreen(false);
        _isFullscreen = false;
      }
      if (_isAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(false);
        _isAlwaysOnTop = false;
      }

      // Don't pop the /player route. With main.dart's Stack-layered
      // PipOverlay this screen stays mounted under the overlay; its
      // build() reacts to pipProvider and hides the local Video so
      // there's no double texture binding. Expand becomes "clear PiP
      // state" (Video re-appears, user is back to fullscreen). Close
      // pops /player from PipOverlay's button.
      await ref.read(pipProvider.notifier).enterPip(
            player: _player,
            controller: _controller,
            title: _currentTitle,
            logo: _currentLogo,
            url: _currentUrl,
            typeName: widget.type.name,
          );
    } finally {
      _pipTransitioning = false;
    }
  }

  // =========================================================================
  //  Chromecast / DLNA callbacks
  // =========================================================================

  /// Called when EITHER a Chromecast session OR a DLNA session has just
  /// started — pause local playback and push the current media URL to the
  /// remote receiver. We dispatch on whichever transport reports itself
  /// connected (the cast button picker only enables one at a time).
  Future<void> _onCastStarted() async {
    _player.pause();

    if (CastService.instance.state.isConnected) {
      final streamType = widget.type == VideoType.live
          ? CastStreamType.live
          : CastStreamType.buffered;
      CastService.instance.loadMedia(
        url: _currentUrl,
        title: _currentTitle,
        imageUrl: _currentLogo,
        streamType: streamType,
      );
    } else if (DlnaService.instance.state.isConnected) {
      // Capture ScaffoldMessenger BEFORE await so we don't have to
      // re-resolve it from a (potentially stale) context after the
      // load attempt completes.
      final messenger = ScaffoldMessenger.of(context);
      final l10n = AppLocalizations.of(context)!;
      try {
        await DlnaService.instance.loadMedia(
          url: _currentUrl,
          title: _currentTitle,
        );
        // TV confirmed PLAYING — tell the user which device has it now.
        if (mounted) {
          final name =
              DlnaService.instance.state.device?.displayName ?? '';
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.castConnectedTo(name)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } on DlnaPlaybackVerificationException catch (e) {
        // TV accepted the SOAP commands but never moved to PLAYING —
        // most common cause: DMR / Smart View / Screen Share toggle on
        // the TV is off, or the TV doesn't accept the source MIME.
        // Resume local playback and surface the hint.
        if (!mounted) return;
        _player.play();
        await DlnaService.instance.disconnect();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'TV oynatmayı başlatamadı (${e.lastState ?? "yanıt yok"}). '
              'TV ayarlarından "DMR / Smart View / DLNA" özelliğinin '
              'açık olduğundan emin ol ve tekrar dene.',
            ),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 6),
          ),
        );
      } catch (_) {
        // Transport / SOAP fault — TV didn't respond at all.
        if (!mounted) return;
        _player.play();
        await DlnaService.instance.disconnect();
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.dlnaConnectFailed),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Called when the remote session ends — resume local playback.
  void _onCastStopped() {
    _player.play();
  }

  // =========================================================================
  //  Fullscreen toggle (desktop only)
  // =========================================================================

  Future<void> _toggleFullscreen() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    await _setFullscreen(!_isFullscreen);
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      await windowManager.setFullScreen(enabled);
      if (mounted) setState(() => _isFullscreen = enabled);
    } catch (_) {
      try {
        final actual = await windowManager.isFullScreen();
        if (mounted) setState(() => _isFullscreen = actual);
      } catch (_) {}
    }
  }

  Future<void> _checkFullscreenState() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    final isFs = await windowManager.isFullScreen();
    if (mounted && isFs != _isFullscreen) setState(() => _isFullscreen = isFs);
  }

  Future<void> _toggleAlwaysOnTop() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    final newValue = !_isAlwaysOnTop;
    try {
      await windowManager.setAlwaysOnTop(newValue);
      if (mounted) setState(() => _isAlwaysOnTop = newValue);
    } catch (_) {
      // Fallback: verify actual state
      try {
        final actual = await windowManager.isAlwaysOnTop();
        if (mounted) setState(() => _isAlwaysOnTop = actual);
      } catch (_) {}
    }
  }

  Future<void> _startWindowDrag() async {
    if (_isInPipMode) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    if (_isFullscreen) return;
    await windowManager.startDragging();
  }

  // =========================================================================
  //  BUILD - SINGLE UNIFIED OVERLAY
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Live-apply subtitle appearance when the user tweaks font size / color /
    // bold / background in the Settings screen while the player is open.
    ref.listen<(int, String, bool, bool)>(
      settingsProvider.select(
        (s) => (
          s.subtitleFontSize,
          s.subtitleColor,
          s.subtitleBold,
          s.subtitleBackgroundEnabled,
        ),
      ),
      (_, _) => _applySubtitleStyle(),
    );

    Widget scaffold = Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        // Dynamic canPop: block pop only when an overlay is open
        canPop: !_showChannelList && !_showEpgGuide && !_showSubtitleSearch,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return; // Pop succeeded, dispose() handles cleanup
          // An overlay is blocking — close the topmost overlay
          if (_showSubtitleSearch) {
            setState(() => _showSubtitleSearch = false);
          } else if (_showEpgGuide) {
            setState(() => _showEpgGuide = false);
          } else if (_showChannelList) {
            setState(() => _showChannelList = false);
          }
          _focusNode.requestFocus();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: MouseRegion(
            onHover: (_) => _showControlsBriefly(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _isPaused ? () => _player.playOrPause() : _toggleControls,
              onDoubleTap: isDesktopPlatform ? _toggleFullscreen : null,
              // Mobile VOD: double-tap left/right halves → seek -10/+10.
              onDoubleTapDown:
                  (isMobilePlatform && widget.type != VideoType.live)
                  ? (details) => _handleDoubleTapSeek(details.globalPosition)
                  : null,
              // Desktop: drag window from anywhere; Mobile: swipe channels
              onPanStart: (isDesktopPlatform && !_isFullscreen && !_isInPipMode)
                  ? (_) => _startWindowDrag()
                  : null,
              // Mobile VOD: vertical drag on left = brightness, right = volume.
              onVerticalDragStart:
                  (isMobilePlatform && widget.type != VideoType.live)
                  ? (d) => _onVerticalDragStart(d.globalPosition)
                  : null,
              onVerticalDragUpdate:
                  (isMobilePlatform && widget.type != VideoType.live)
                  ? (d) => _onVerticalDragUpdate(d.primaryDelta ?? 0)
                  : null,
              onVerticalDragEnd:
                  (isMobilePlatform &&
                      widget.type == VideoType.live &&
                      widget.channels != null)
                  ? (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -300) {
                        // Swipe up → next channel
                        _channelDown();
                      } else if (velocity > 300) {
                        // Swipe down → previous channel
                        _channelUp();
                      }
                    }
                  : null,
              child: Stack(
                children: [
                  // -- Video layer (no native controls - we use custom overlay) --
                  // Hidden while PiP is active so PipOverlay's Video has
                  // the only binding to _controller — two simultaneous
                  // Video widgets bound to the same controller cause
                  // texture conflicts on media_kit (frozen / gray frame).
                  if (ref.watch(pipProvider) == null)
                    Center(
                      child: Video(
                        key: _videoKey,
                        controller: _controller,
                        fill: Colors.black,
                        // User-selectable scaling. Default 'contain'
                        // (letter/pillar-box). 'cover' crops to fill,
                        // 'fill' stretches — for streams whose declared
                        // aspect ratio leaves the picture small.
                        fit: _boxFitFor(
                            ref.watch(settingsProvider).videoFitMode),
                        controls: NoVideoControls,
                        // media_kit renders subtitles via a Flutter widget by
                        // default — NOT via mpv/libass. So style/position must
                        // live here, not in mpv setProperty calls. Cached so
                        // rebuilds reuse the same object (no per-frame churn).
                        subtitleViewConfiguration: _cachedSubtitleConfig,
                      ),
                    ),

                  // -- Buffering indicator -----------------------------------
                  if (_isBuffering && !_showBufferingError)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    ),

                  // -- Persistent "casting" banner ---------------------------
                  // Always visible (independent of the auto-hiding
                  // controls) so the user can SEE that playback has been
                  // handed off to a TV and the phone is intentionally
                  // idle. Mobile only — desktop uses HDMI, never casts.
                  if (Platform.isAndroid || Platform.isIOS)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: _CastingBanner(),
                      ),
                    ),

                  // -- Gesture HUD (brightness / volume / seek) --------------
                  if (_gestureHudIcon != null && _gestureHudText != null)
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_gestureHudIcon, color: Colors.white, size: 36),
                              const SizedBox(height: 6),
                              Text(
                                _gestureHudText!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (_gestureHudValue != null) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: 120,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: _gestureHudValue!,
                                      minHeight: 3,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.2),
                                      valueColor: const AlwaysStoppedAnimation(
                                        AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                  // -- Buffering timeout error --------------------------------
                  if (!_isInPipMode && _showBufferingError)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context)!.connectionTimedOut,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.streamLoadFailed,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() => _showBufferingError = false);
                                _player.open(Media(_currentUrl));
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar Dene'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // -- SINGLE unified controls overlay -----------------------
                  // Hide all controls when in Android PiP mode (window too small)
                  if (!_isInPipMode)
                    FadeTransition(
                      opacity: _controlsFade,
                      child: IgnorePointer(
                        ignoring: !_showControls && !_isPaused,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black87,
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black87,
                              ],
                              stops: [0.0, 0.2, 0.65, 1.0],
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildTopBar(l10n),
                              const Spacer(),
                              // Pause info badge (shows after 2s delay, VOD only — Netflix style)
                              if (_showPauseBadge &&
                                  widget.type != VideoType.live)
                                _buildPauseInfoBadge(l10n),
                              if (_showPauseBadge &&
                                  widget.type != VideoType.live)
                                const SizedBox(height: 12),
                              // Bottom bar wrapped in Focus to detect when buttons are focused
                              Focus(
                                skipTraversal: true,
                                onFocusChange: _onControlsFocusChange,
                                child: _buildBottomBar(l10n),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // -- Channel info overlay (live TV channel switch) ----------
                  if (!_isInPipMode &&
                      _showChannelInfo &&
                      widget.type == VideoType.live)
                    _buildChannelInfoOverlay(),

                  // -- Next episode overlay ----------------------------------
                  if (!_isInPipMode &&
                      widget.type == VideoType.series &&
                      widget.nextEpisodeTitle != null &&
                      _showNextOverlay)
                    Positioned(
                      bottom: 110,
                      right: 24,
                      child: _buildNextOverlay(l10n),
                    ),

                  // -- Skip intro button (series only, inside marked range) --
                  if (!_isInPipMode &&
                      _showSkipIntro &&
                      widget.type == VideoType.series &&
                      !_showNextOverlay &&
                      ref.watch(settingsProvider).showSkipIntroButton)
                    Positioned(
                      bottom: 110,
                      right: 24,
                      child: _buildSkipIntroButton(),
                    ),

                  // -- Channel list overlay (live TV) --------------------------
                  if (!_isInPipMode &&
                      _showChannelList &&
                      widget.type == VideoType.live &&
                      widget.channels != null &&
                      widget.channels!.isNotEmpty)
                    Positioned.fill(
                      child: Row(
                        children: [
                          // Tap-to-close area (left side)
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _showChannelList = false),
                              child: Container(color: Colors.black26),
                            ),
                          ),
                          // The overlay itself
                          ChannelListOverlay(
                            channels: widget.channels!,
                            currentChannelIndex: _channelIndex,
                            categoryNames: widget.categoryNames,
                            onChannelSelected: (idx) {
                              setState(() => _showChannelList = false);
                              _switchChannel(idx);
                            },
                            onClose: () =>
                                setState(() => _showChannelList = false),
                          ),
                        ],
                      ),
                    ),

                  // -- EPG guide overlay (live TV) ----------------------------
                  if (!_isInPipMode &&
                      _showEpgGuide &&
                      widget.type == VideoType.live)
                    Positioned.fill(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final currentStreamId =
                              widget.channels != null &&
                                  _channelIndex < widget.channels!.length
                              ? widget.channels![_channelIndex].streamId
                              : 0;
                          final programsAsync = ref.watch(
                            programsProvider(currentStreamId),
                          );
                          return programsAsync.when(
                            data: (programs) => EpgOverlay(
                              programs: programs,
                              channelName: _currentTitle,
                              channelLogo: _currentLogo,
                              onClose: () =>
                                  setState(() => _showEpgGuide = false),
                              onCatchUp: (p) =>
                                  _startTimeshift(currentStreamId, p),
                            ),
                            loading: () => EpgOverlay(
                              programs: const [],
                              channelName: _currentTitle,
                              channelLogo: _currentLogo,
                              onClose: () =>
                                  setState(() => _showEpgGuide = false),
                            ),
                            error: (_, _) => EpgOverlay(
                              programs: const [],
                              channelName: _currentTitle,
                              channelLogo: _currentLogo,
                              onClose: () =>
                                  setState(() => _showEpgGuide = false),
                            ),
                          );
                        },
                      ),
                    ),

                  // -- OpenSubtitles search overlay (VOD only) -----------
                  if (!_isInPipMode &&
                      _showSubtitleSearch &&
                      widget.type != VideoType.live)
                    Positioned.fill(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final settings = ref.watch(settingsProvider);
                          final service = OpenSubtitlesService.getInstance(
                            settings.opensubtitlesApiKey,
                          );
                          if (service == null) {
                            // No API key configured
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() => _showSubtitleSearch = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'OpenSubtitles API key gerekli — Ayarlar > Altyazı',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            });
                            return const SizedBox.shrink();
                          }
                          return SubtitleSearchOverlay(
                            title: widget.title,
                            year: widget.year,
                            preferredLanguage:
                                settings.subtitlePreferredLanguage,
                            service: service,
                            onSubtitleSelected: (vttContent, label) {
                              _player.setSubtitleTrack(
                                SubtitleTrack.data(vttContent, title: label),
                              );
                              _applySubtitleStyle();
                            },
                            onClose: () =>
                                setState(() => _showSubtitleSearch = false),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // On desktop, wrap with DragToResizeArea so user can resize from edges
    if (isDesktopPlatform && !_isFullscreen && !_isInPipMode) {
      return DragToResizeArea(child: scaffold);
    }
    return scaffold;
  }

  // =========================================================================
  //  Top bar
  // =========================================================================

  Widget _buildTopBar(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Back
            _DpadIconBtn(
              icon: Icons.arrow_back,
              onTap: () {
                _saveProgress();
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(width: 12),

            // Logo
            if (_currentLogo != null && _currentLogo!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: _currentLogo!,
                  width: 30,
                  height: 30,
                  memCacheWidth: 96,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (_currentLogo != null && _currentLogo!.isNotEmpty)
              const SizedBox(width: 12),

            // Title + program info
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => _startWindowDrag(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.type == VideoType.live &&
                        widget.currentProgramTitle != null)
                      _buildLiveProgramInfo(),
                    if (widget.category != null)
                      Text(
                        widget.category!,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Sleep timer button — shows active countdown in tooltip.
            _DpadIconBtn(
              icon: _sleepTimerIcon(),
              onTap: _showSleepTimerPicker,
              tint: _isSleepTimerActive ? AppColors.primary : null,
            ),
            const SizedBox(width: 8),

            // Skip-Intro marker manager — series only. Bookmark icon is
            // filled if this series already has a saved intro range so
            // the user can tell at a glance whether the floating
            // "Skip Intro" affordance will appear on subsequent
            // episodes.
            if (widget.type == VideoType.series &&
                widget.parentStreamId != null) ...[
              _DpadIconBtn(
                icon: (_introStartMs != null && _introEndMs != null)
                    ? Icons.bookmark
                    : Icons.bookmark_outline,
                onTap: _showIntroMarkerDialog,
                tint: (_introStartMs != null && _introEndMs != null)
                    ? AppColors.primary
                    : null,
              ),
              const SizedBox(width: 8),
            ],

            // PiP button (supported desktop platforms + Android)
            if (isPipSupported) ...[
              _DpadIconBtn(
                icon: Icons.picture_in_picture_alt,
                onTap: _enterPipMode,
              ),
              const SizedBox(width: 8),
            ],

            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _typeBadgeColor(),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.type == VideoType.live) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    _typeBadgeLabel(l10n),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveProgramInfo() {
    final timeStr = widget.programStart != null
        ? DateFormat('HH:mm').format(widget.programStart!)
        : '';
    final endStr = widget.programEnd != null
        ? ' - ${DateFormat('HH:mm').format(widget.programEnd!)}'
        : '';
    return Text(
      '$timeStr$endStr  ${widget.currentProgramTitle ?? ''}',
      style: const TextStyle(color: Colors.white60, fontSize: 11),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // =========================================================================
  //  Pause info badge (compact, above bottom bar)
  // =========================================================================

  Widget _buildPauseInfoBadge(AppLocalizations l10n) {
    final remaining = _dur - _pos;
    final hasMetadata =
        widget.plot != null ||
        widget.genre != null ||
        widget.year != null ||
        widget.rating != null;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - value)),
              child: child,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Frosted(
              sigma: 24,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xEB101014),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster thumbnail
                    if (widget.logo != null && widget.logo!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: widget.logo!,
                          width: 80,
                          height: 120,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    if (widget.logo != null && widget.logo!.isNotEmpty)
                      const SizedBox(width: 16),

                    // Info column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title
                          Text(
                            _currentTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Meta row: year, rating, genre
                          if (hasMetadata)
                            Row(
                              children: [
                                if (widget.year != null)
                                  Text(
                                    widget.year!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                if (widget.rating != null &&
                                    widget.rating! > 0) ...[
                                  if (widget.year != null)
                                    const SizedBox(width: 10),
                                  const Icon(
                                    Icons.star,
                                    color: AppColors.gold,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    widget.rating!.toStringAsFixed(1),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (widget.genre != null) ...[
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      widget.genre!,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),

                          // Plot (2-line clamp)
                          if (widget.plot != null &&
                              widget.plot!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.plot!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          // Time info: current / duration (remaining)
                          if (_dur.inSeconds > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_fmt(_pos)} / ${_fmt(_dur)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                if (remaining.inSeconds > 0) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${_fmt(remaining)} ${l10n.remaining})',
                                    style: TextStyle(
                                      color: Colors.red.withValues(alpha: 0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  //  Bottom bar - UNIFIED with direct audio/subtitle/speed buttons
  // =========================================================================

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // -- Progress --
          widget.type == VideoType.live
              ? _buildLiveProgressBar()
              : _buildVodProgressBar(),
          const SizedBox(height: 10),

          // -- Button row --
          Row(
            children: [
              // Play/Pause button (focusable)
              _DpadIconBtn(
                icon: _isPaused ? Icons.play_arrow : Icons.pause,
                onTap: () => _player.playOrPause(),
                isPrimary: true,
                size: 28,
                focusNode: _playPauseFocusNode,
              ),
              const SizedBox(width: 12),

              // Previous episode (series only)
              if (widget.type == VideoType.series &&
                  widget.onPrevEpisode != null) ...[
                _DpadIconBtn(
                  icon: Icons.skip_previous,
                  onTap: widget.onPrevEpisode!,
                ),
                const SizedBox(width: 8),
              ],

              // Seek backward
              if (widget.type != VideoType.live) ...[
                _DpadIconBtn(
                  icon: Icons.replay_10,
                  onTap: () {
                    _player.seek(_pos - const Duration(seconds: 10));
                    _showControlsBriefly();
                  },
                ),
                const SizedBox(width: 8),

                // Seek forward
                _DpadIconBtn(
                  icon: Icons.forward_10,
                  onTap: () {
                    _player.seek(_pos + const Duration(seconds: 10));
                    _showControlsBriefly();
                  },
                ),
              ],

              // Next episode (series only)
              if (widget.type == VideoType.series &&
                  widget.onNextEpisode != null) ...[
                const SizedBox(width: 8),
                _DpadIconBtn(icon: Icons.skip_next, onTap: _triggerNext),
              ],

              // Action buttons grouped into a horizontally
              // scrollable strip on the right. Portrait phones
              // can't fit 10+ buttons in one row — without scroll
              // the last ones got clipped behind the screen edge
              // and were impossible to reach. SingleChildScrollView
              // with reverse:false + Expanded gives the strip the
              // full remaining width and lets the user pan.
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
              // ─── Direct action buttons (D-pad accessible) ───

              // Audio track button
              _DpadIconBtn(
                icon: Icons.audiotrack,
                label: l10n.audioTrack,
                onTap: () => _showTrackPicker('audio'),
              ),
              const SizedBox(width: 6),

              // Quality / bitrate selector. Only rendered when the
              // stream actually exposes multiple video tracks (HLS
              // ABR ladders typically do, progressive single-file
              // VOD doesn't). Hiding the button when there's nothing
              // to pick avoids a dead control on the overlay.
              if (_player.state.tracks.video
                      .where((t) => t.id != 'no')
                      .length >
                  1) ...[
                _DpadIconBtn(
                  icon: Icons.high_quality_outlined,
                  label: l10n.streamQuality,
                  onTap: _showQualityPicker,
                ),
                const SizedBox(width: 6),
              ],

              // Subtitle button
              _DpadIconBtn(
                icon: Icons.subtitles_outlined,
                label: l10n.subtitle,
                onTap: () => _showTrackPicker('subtitle'),
              ),
              const SizedBox(width: 6),

              // Online subtitle search (VOD only, and only when an
              // OpenSubtitles API key is configured — otherwise the
              // button just popped a snackbar telling the user to go
              // configure it, which read like an "error" out of
              // nowhere).
              if (widget.type != VideoType.live &&
                  (ref.watch(settingsProvider).opensubtitlesApiKey ?? '')
                      .isNotEmpty) ...[
                _DpadIconBtn(
                  icon: Icons.closed_caption_outlined,
                  onTap: () => setState(
                    () => _showSubtitleSearch = !_showSubtitleSearch,
                  ),
                ),
                const SizedBox(width: 6),
              ],

              // Speed button (only for VOD)
              if (widget.type != VideoType.live) ...[
                _DpadIconBtn(icon: Icons.speed, onTap: _showSpeedPicker),
                const SizedBox(width: 6),
              ],

              // Stream stats (codec / resolution / bitrate / dropped frames)
              _DpadIconBtn(icon: Icons.info_outline, onTap: _showStreamStatsDialog),
              const SizedBox(width: 6),

              // Video fit / zoom toggle — cycles contain → cover →
              // fill. Lets the user blow up streams whose declared
              // aspect ratio leaves the picture small with black bars.
              _DpadIconBtn(
                icon: _fitIcon(ref.watch(settingsProvider).videoFitMode),
                label: l10n.videoFit,
                onTap: _cycleVideoFit,
              ),
              const SizedBox(width: 6),

              // Channel list button (live TV only)
              if (widget.type == VideoType.live &&
                  widget.channels != null &&
                  widget.channels!.isNotEmpty) ...[
                _DpadIconBtn(
                  icon: Icons.list,
                  onTap: () =>
                      setState(() => _showChannelList = !_showChannelList),
                ),
                const SizedBox(width: 6),
              ],

              // EPG guide button (live TV only)
              if (widget.type == VideoType.live) ...[
                _DpadIconBtn(
                  icon: Icons.calendar_month,
                  onTap: () => setState(() => _showEpgGuide = !_showEpgGuide),
                ),
                const SizedBox(width: 6),
              ],

              // Chromecast button (mobile only — desktop uses HDMI)
              if (Platform.isAndroid || Platform.isIOS) ...[
                CastButton(
                  onCastStarted: _onCastStarted,
                  onCastStopped: _onCastStopped,
                ),
                const SizedBox(width: 2),
              ],

              // Volume button
              _DpadIconBtn(
                icon: _volume == 0
                    ? Icons.volume_off
                    : _volume < 50
                    ? Icons.volume_down
                    : Icons.volume_up,
                onTap: () {
                  // Toggle mute on click
                  _player.setVolume(_volume > 0 ? 0 : 100);
                },
              ),

              // Always on top toggle (desktop only)
              if (Platform.isWindows ||
                  Platform.isLinux ||
                  Platform.isMacOS) ...[
                const SizedBox(width: 6),
                _DpadIconBtn(
                  icon: _isAlwaysOnTop
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  onTap: _toggleAlwaysOnTop,
                ),
              ],

              // Fullscreen toggle (desktop only)
              if (Platform.isWindows ||
                  Platform.isLinux ||
                  Platform.isMacOS) ...[
                const SizedBox(width: 6),
                _DpadIconBtn(
                  icon: _isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  onTap: _toggleFullscreen,
                ),
              ],
                    ], // end inner Row
                  ),
                ),
              ), // end Expanded SingleChildScrollView
            ], // end outer Row
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  VOD progress bar
  // =========================================================================

  Widget _buildVodProgressBar() {
    final maxVal = _dur.inSeconds > 0 ? _dur.inSeconds.toDouble() : 1.0;
    final curVal = _pos.inSeconds.toDouble().clamp(0.0, maxVal);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(_pos),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            if (_dur.inSeconds > 0)
              Text(
                '-${_fmt(_dur - _pos)}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: Colors.white12,
            thumbColor: AppColors.primary,
          ),
          // On Android TV the Slider is excluded from D-pad traversal: a
          // focused Slider eats Left/Right to scrub, trapping focus so the
          // remote can't move between the bottom-bar buttons past it. TV
          // seeking is done with the D-pad arrows on the video surface
          // (accumulated seek), so the bar stays a pure progress indicator
          // there while remaining interactive for mouse/touch elsewhere.
          child: ExcludeFocus(
            excluding: PlatformHelper.isTV,
            child: Slider(
              value: curVal,
              max: maxVal,
              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  //  Live progress bar
  // =========================================================================

  Widget _buildLiveProgressBar() {
    return Column(
      children: [
        if (widget.programStart != null && widget.programEnd != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('HH:mm').format(widget.programStart!),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                if (widget.currentProgramTitle != null)
                  Expanded(
                    child: Text(
                      widget.currentProgramTitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  DateFormat('HH:mm').format(widget.programEnd!),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: _liveProgress,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 3,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  //  Channel info overlay – frosted glass at bottom (TV-style)
  // =========================================================================

  Widget _buildChannelInfoOverlay() {
    final channels = widget.channels;
    final chNum = channels != null
        ? '${_channelIndex + 1} / ${channels.length}'
        : '';
    final l10n = AppLocalizations.of(context)!;

    // EPG progress for current program
    double epgProgress = 0;
    if (_currentProgram != null) {
      final now = DateTime.now();
      final total = _currentProgram!.stop
          .difference(_currentProgram!.start)
          .inSeconds;
      final elapsed = now.difference(_currentProgram!.start).inSeconds;
      if (total > 0) epgProgress = (elapsed / total).clamp(0.0, 1.0);
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: _showChannelInfo ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          child: Frosted(
            sigma: 20,
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
                border: const Border(
                  top: BorderSide(color: Colors.white10, width: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Left: Logo + Channel number ──
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentLogo != null && _currentLogo!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: _currentLogo!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            memCacheWidth: 156,
                            errorWidget: (_, _, _) => Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevatedDark,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.tv,
                                color: Colors.white24,
                                size: 26,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevatedDark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.tv,
                            color: Colors.white38,
                            size: 26,
                          ),
                        ),
                      if (chNum.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          chNum,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 20),

                  // ── Center: Channel name + EPG info ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Channel name + LIVE badge
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _currentTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: Colors.white,
                                    size: 6,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'CANLI',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Current program info
                        if (_currentProgram != null) ...[
                          Row(
                            children: [
                              Text(
                                '${DateFormat('HH:mm').format(_currentProgram!.start)} - ${DateFormat('HH:mm').format(_currentProgram!.stop)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _currentProgram!.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: epgProgress,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary,
                              ),
                              minHeight: 3,
                            ),
                          ),
                        ] else ...[
                          Text(
                            l10n.noProgramGuide,
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 12,
                            ),
                          ),
                        ],

                        // Next program
                        if (_nextProgram != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.upNextLabel,
                                style: const TextStyle(
                                  color: Colors.white30,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${DateFormat('HH:mm').format(_nextProgram!.start)} ',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _nextProgram!.title,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 16),

                  // ── Right: Up/Down arrows ──
                  if (channels != null && channels.isNotEmpty)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.white54,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white54,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  //  Next episode overlay
  // =========================================================================

  Widget _buildNextOverlay(AppLocalizations l10n) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.nextEpisode,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '${_nextCountdown}s',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.nextEpisodeTitle!,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _nextCountdown / 15.0,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  autofocus: true,
                  onPressed: _triggerNext,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(l10n.playNow),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _cancelNext,
                child: Text(
                  l10n.cancel,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
//  CASTING BANNER — persistent "now casting to <device>" strip
// ===========================================================================

/// Thin always-on bar shown at the top of the player while a
/// Chromecast OR DLNA session is active. Listens to both service
/// notifiers and merges them so a single banner covers either
/// transport. Hidden (zero-size) when nothing is connected.
class _CastingBanner extends StatelessWidget {
  const _CastingBanner();

  @override
  Widget build(BuildContext context) {
    final cast = CastService.instance;
    final dlna = DlnaService.instance;
    return ValueListenableBuilder<CastState>(
      valueListenable: cast.stateNotifier,
      builder: (context, castState, _) {
        return ValueListenableBuilder<DlnaState>(
          valueListenable: dlna.stateNotifier,
          builder: (context, dlnaState, _) {
            final castOn = castState.isConnected;
            final dlnaOn = dlnaState.isConnected;
            if (!castOn && !dlnaOn) return const SizedBox.shrink();
            final name = castOn
                ? (castState.device?.name ?? '')
                : (dlnaState.device?.displayName ?? '');
            final l10n = AppLocalizations.of(context)!;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.black.withValues(alpha: 0.65),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cast_connected,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.castingBanner(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ===========================================================================
//  D-PAD FOCUSABLE ICON BUTTON - works with mouse, touch, AND remote
// ===========================================================================

class _DpadIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool isPrimary;
  final double size;
  final FocusNode? focusNode;
  final Color? tint;

  const _DpadIconBtn({
    required this.icon,
    required this.onTap,
    this.label,
    this.isPrimary = false,
    this.size = 22,
    this.focusNode,
    this.tint,
  });

  @override
  State<_DpadIconBtn> createState() => _DpadIconBtnState();
}

class _DpadIconBtnState extends State<_DpadIconBtn> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: widget.label != null ? 12 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: widget.isPrimary
                  ? (isActive
                        ? AppColors.primary.withValues(alpha: 0.9)
                        : AppColors.primary)
                  : (isActive
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? AppColors.primary : Colors.transparent,
                width: _isFocused ? 2 : 0,
              ),
              boxShadow: widget.isPrimary
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: widget.tint ?? Colors.white,
                  size: widget.size,
                ),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
//  Focusable track tile (for audio/subtitle picker dialog)
// ===========================================================================

class _FocusableTrackTile extends StatefulWidget {
  final String title;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _FocusableTrackTile({
    required this.title,
    required this.isSelected,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_FocusableTrackTile> createState() => _FocusableTrackTileState();
}

class _FocusableTrackTileState extends State<_FocusableTrackTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isFocused;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _isFocused
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: isActive ? AppColors.primary : AppColors.textDark,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
//  Focusable speed chip
// ===========================================================================

class _FocusableSpeedChip extends StatefulWidget {
  final double speed;
  final bool isActive;
  final bool autofocus;
  final VoidCallback onTap;

  const _FocusableSpeedChip({
    required this.speed,
    required this.isActive,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_FocusableSpeedChip> createState() => _FocusableSpeedChipState();
}

class _FocusableSpeedChipState extends State<_FocusableSpeedChip> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = widget.isActive || _isFocused;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted ? AppColors.primary : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? AppColors.primary
                  : (widget.isActive
                        ? AppColors.primary
                        : AppColors.borderDark),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Text(
            '${widget.speed}x',
            style: TextStyle(
              color: isHighlighted ? Colors.white : AppColors.textSecondaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
