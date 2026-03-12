import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
import 'package:lifeostv/presentation/widgets/player/channel_list_overlay.dart';
import 'package:lifeostv/presentation/widgets/content/program_guide.dart';
import 'package:lifeostv/presentation/widgets/player/epg_overlay.dart';
import 'package:lifeostv/presentation/widgets/player/subtitle_search_overlay.dart';
import 'package:lifeostv/data/services/opensubtitles_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/utils/gpu_detector.dart';
import 'package:lifeostv/utils/mpv_config.dart';
import 'package:lifeostv/data/services/cast_service.dart';
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

  /// Channel list for live TV channel switching (D-pad up/down)
  final List<PlayerChannel>? channels;
  final int? currentChannelIndex;

  /// Category ID → Name map for channel list overlay
  final Map<String, String>? categoryNames;

  /// Existing player/controller from PiP expansion (reuse instead of creating new)
  final Player? existingPlayer;
  final VideoController? existingController;

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
    this.channels,
    this.currentChannelIndex,
    this.categoryNames,
    this.existingPlayer,
    this.existingController,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

// ---------------------------------------------------------------------------
//  State
// ---------------------------------------------------------------------------

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with SingleTickerProviderStateMixin {
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
  Timer? _posUpdateTimer; // Throttled UI updates for position

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

  // -- Channel switching (live TV only) ------------------------------------
  late int _channelIndex;
  late String _currentTitle;
  late String? _currentLogo;
  bool _showChannelInfo = false;
  Timer? _channelInfoTimer;

  // PiP transfer flag – when true, dispose() won't destroy the player
  bool _transferredToPip = false;
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

  // -- Always on top (desktop only) -------------------------------------------
  bool _isAlwaysOnTop = false;

  // =========================================================================
  //  Lifecycle
  // =========================================================================

  @override
  void initState() {
    super.initState();

    // Hide status bar & navigation bar on mobile (immersive mode)
    if (isMobilePlatform) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      duration: const Duration(milliseconds: 250),
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
      _saveProgressTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _saveProgress(),
      );
    }
  }

  @override
  void dispose() {
    _saveProgress();
    // Restore status bar & navigation bar on mobile
    if (isMobilePlatform) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    _posUpdateTimer?.cancel();
    _channelInfoTimer?.cancel();
    if (!_transferredToPip) {
      // Stop playback immediately, then dispose
      _player.stop();
      _player.dispose();
    }
    _setPlayerActive(false);
    _hideTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgressTimer?.cancel();
    _nextTimer?.cancel();
    _pauseBadgeTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    _controlsAnim.dispose();
    _focusNode.dispose();
    _playPauseFocusNode.dispose();
    super.dispose();
  }

  // =========================================================================
  //  Subtitle styling helper
  // =========================================================================

  Future<void> _applySubtitleStyle() async {
    final mpv = _player.platform;
    if (mpv is! NativePlayer) return;
    final settings = ref.read(settingsProvider);
    // mpv expects color in #AARRGGBB format
    final subColor = settings.subtitleColor.length == 7
        ? '#FF${settings.subtitleColor.substring(1)}'
        : settings.subtitleColor;
    await mpv.setProperty('sub-font-size', settings.subtitleFontSize.toString());
    await mpv.setProperty('sub-color', subColor);
    await mpv.setProperty('sub-bold', settings.subtitleBold ? 'yes' : 'no');
    await mpv.setProperty(
      'sub-back-color',
      settings.subtitleBackgroundEnabled ? '#80000000' : '#00000000',
    );
  }

  // =========================================================================
  //  Player init
  // =========================================================================

  Future<void> _initPlayer() async {
    final settings = ref.read(settingsProvider);

    // Reuse existing player from PiP expansion
    if (widget.existingPlayer != null && widget.existingController != null) {
      ref.read(pipProvider.notifier).detachPip();
      _player = widget.existingPlayer!;
      _controller = widget.existingController!;
      // Skip configuration and media open – player is already running
      _attachStreamListeners();
      _resetHideTimer();
      return;
    }

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
        bufferSize: Platform.isLinux ? 8 * 1024 * 1024 : 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    // ── mpv performance options (auto-configured per GPU) ──
    if (_player.platform is NativePlayer) {
      final mpv = _player.platform! as NativePlayer;
      final gpu = await GpuDetector.detect();
      await MpvConfig.applyOptimal(mpv, gpu);

      if (widget.type == VideoType.live) {
        // Live TV: aggressive low-latency
        await mpv.setProperty('profile', 'low-latency');
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('cache-secs', '2');
        await mpv.setProperty('demuxer-max-bytes', '8MiB');
        await mpv.setProperty('demuxer-max-back-bytes', '4MiB');
        await mpv.setProperty('demuxer-readahead-secs', '2');
      } else {
        // VOD
        await mpv.setProperty('cache', 'yes');
        await mpv.setProperty('cache-secs', '15');
        await mpv.setProperty('demuxer-max-bytes', '32MiB');
        await mpv.setProperty('demuxer-max-back-bytes', '16MiB');
      }

      // Disable subtitles by default — user can enable via track picker
      await mpv.setProperty('sid', 'no');

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
        if (widget.type == VideoType.series &&
            widget.onNextEpisode != null &&
            _dur.inSeconds > 0) {
          final remaining = _dur.inSeconds - p.inSeconds;
          if (remaining <= 45 &&
              remaining > 0 &&
              !_showNextOverlay &&
              !_nextTriggered) {
            _startNextCountdown();
          }
        }
      }),
    );

    // Throttled position UI update (every 500ms)
    _posUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _rawPos != _pos) {
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
        setState(() => _isPaused = !playing);
        if (!playing) {
          _controlsAnim.forward();
          setState(() => _showControls = true);
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
          if (_showPauseBadge) setState(() => _showPauseBadge = false);
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
            if (_showBufferingError)
              setState(() => _showBufferingError = false);
          }
        }
      }),
    );

    _subs.add(
      _player.stream.volume.listen((v) {
        if (mounted) setState(() => _volume = v);
      }),
    );
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
          _pos.inMilliseconds,
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
            _pos.inMilliseconds,
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
    } else {
      _controlsAnim.forward();
      setState(() => _showControls = true);
      _resetHideTimer();
    }
  }

  void _showControlsBriefly() {
    if (!_showControls) {
      _controlsAnim.forward();
      setState(() => _showControls = true);
    }
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isPaused) {
        _controlsAnim.reverse();
        setState(() => _showControls = false);
      }
    });
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

    // Play / Pause (select/enter on video area, or space)
    if (k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }

    // Select/enter when controls hidden → show controls
    if ((k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) &&
        !_showControls) {
      _showControlsBriefly();
      // Move focus to play/pause button
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
      final target = _pos - const Duration(seconds: 10);
      setState(() => _pos = target); // Immediate UI feedback
      _player.seek(target);
      _showControlsBriefly();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      final target = _pos + const Duration(seconds: 10);
      setState(() => _pos = target); // Immediate UI feedback
      _player.seek(target);
      _showControlsBriefly();
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

    // Any other key → show controls
    _showControlsBriefly();
    return KeyEventResult.ignored;
  }

  // Focus node for the play/pause button (so we can programmatically focus it)
  final _playPauseFocusNode = FocusNode();

  // =========================================================================
  //  Track pickers (audio/subtitle) - as full-screen dialog for D-pad
  // =========================================================================

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
        child: SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
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
                          } else {
                            _player.setSubtitleTrack(t as SubtitleTrack);
                            _applySubtitleStyle();
                          }
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
    _pipEventChannel.receiveBroadcastStream().listen((event) {
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

      _transferredToPip = true;
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

      // Cancel all subscriptions so this State doesn't fight with PiP
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
      _epgSub?.cancel();
      _posUpdateTimer?.cancel();

      await ref
          .read(pipProvider.notifier)
          .enterPip(
            player: _player,
            controller: _controller,
            title: _currentTitle,
            logo: _currentLogo,
            url: _currentUrl,
            typeName: widget.type.name,
          );

      // Pop back to previous screen (use Navigator directly to bypass GoRouter issues)
      if (mounted) Navigator.of(context).pop();
    } finally {
      _pipTransitioning = false;
    }
  }

  // =========================================================================
  //  Chromecast callbacks
  // =========================================================================

  /// Called when cast session starts — pause local player, send media to cast.
  void _onCastStarted() {
    // Pause local playback
    _player.pause();

    // Send the current media URL to the cast device
    final castService = CastService.instance;
    final streamType = widget.type == VideoType.live
        ? CastStreamType.live
        : CastStreamType.buffered;

    castService.loadMedia(
      url: _currentUrl,
      title: _currentTitle,
      imageUrl: _currentLogo,
      streamType: streamType,
    );
  }

  /// Called when cast session ends — resume local player.
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
              // Desktop: drag window from anywhere; Mobile: swipe channels
              onPanStart: (isDesktopPlatform && !_isFullscreen && !_isInPipMode)
                  ? (_) => _startWindowDrag()
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
                  Center(
                    child: Video(
                      controller: _controller,
                      fill: Colors.black,
                      controls: NoVideoControls,
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
                            const Text(
                              'Bağlantı zaman aşımına uğradı',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Stream yüklenemedi. Tekrar deneyin.',
                              style: TextStyle(
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
                            ),
                            loading: () => EpgOverlay(
                              programs: const [],
                              channelName: _currentTitle,
                              channelLogo: _currentLogo,
                              onClose: () =>
                                  setState(() => _showEpgGuide = false),
                            ),
                            error: (_, __) => EpgOverlay(
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
                child: Image.network(
                  _currentLogo!,
                  width: 30,
                  height: 30,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
                        child: Image.network(
                          widget.logo!,
                          width: 80,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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

              const Spacer(),

              // ─── Direct action buttons (D-pad accessible) ───

              // Audio track button
              _DpadIconBtn(
                icon: Icons.audiotrack,
                label: l10n.audioTrack,
                onTap: () => _showTrackPicker('audio'),
              ),
              const SizedBox(width: 6),

              // Subtitle button
              _DpadIconBtn(
                icon: Icons.subtitles_outlined,
                label: l10n.subtitle,
                onTap: () => _showTrackPicker('subtitle'),
              ),
              const SizedBox(width: 6),

              // Online subtitle search (VOD only)
              if (widget.type != VideoType.live) ...[
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
            ],
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
          child: Slider(
            value: curVal,
            max: maxVal,
            onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
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
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                          child: Image.network(
                            _currentLogo!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
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
                              const Text(
                                'Sıradaki: ',
                                style: TextStyle(
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
//  D-PAD FOCUSABLE ICON BUTTON - works with mouse, touch, AND remote
// ===========================================================================

class _DpadIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final bool isPrimary;
  final double size;
  final FocusNode? focusNode;

  const _DpadIconBtn({
    required this.icon,
    required this.onTap,
    this.label,
    this.isPrimary = false,
    this.size = 22,
    this.focusNode,
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
                Icon(widget.icon, color: Colors.white, size: widget.size),
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
