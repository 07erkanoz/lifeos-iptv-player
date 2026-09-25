import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/data/services/subtitle_track_matcher.dart';
import 'package:lifeostv/presentation/controllers/tv_subtitle_controller.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:drift/drift.dart'
    show OrderingTerm, ComparableExpr, BooleanExpressionOperators;
import 'package:lifeostv/presentation/widgets/player/channel_list_overlay.dart';
import 'package:lifeostv/presentation/widgets/player/epg_overlay.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/presentation/state/epg_request_provider.dart';
import 'package:lifeostv/data/services/media_request.dart';
import 'package:lifeostv/data/services/cast_service.dart';
import 'package:lifeostv/data/services/dlna_service.dart';
import 'package:lifeostv/data/services/m3u_catchup.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart'
    show activeProfileIdProvider;
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_config.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_failure.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/core/playback_signal.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/controllers/playback_seek_controller.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart'
    show VideoType, PlayerChannel;
import 'package:lifeostv/presentation/widgets/player/cast_button.dart';
import 'package:lifeostv/presentation/widgets/player/tv_player_action_button.dart';

/// Android-TV-only video player backed by ExoPlayer (via `video_player`).
///
/// Why a separate screen: media_kit/mpv renders every frame into a Flutter
/// GL texture and runs its shader chain — smooth on desktop/mobile but a
/// stutter ceiling on weak Android-TV GPUs. ExoPlayer decodes via MediaCodec
/// straight to a Surface (the efficient Android path, like TiViMate). This
/// screen is routed ONLY when `Android && PlatformHelper.isTV`; every other
/// platform keeps the full media_kit [VideoPlayerScreen] untouched.
///
/// D-pad controls, live channel/EPG panels, audio/subtitle and quality
/// selection and Cast/DLNA handoff share this route.
class TvVideoPlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String? fallbackStreamUrl;
  final Map<String, String> httpHeaders;
  final int streamId;
  final int? accountId;
  final String title;
  final VideoType type;
  final String? logo;
  final String? plot;
  final String? genre;
  final String? year;
  final double? rating;
  final String? currentProgramTitle;
  final Duration? startPosition;
  final int? parentStreamId;
  final bool saveSeriesSummary;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPrevEpisode;
  final String? nextEpisodeTitle;
  final String? previousEpisodeTitle;
  final List<PlayerChannel>? channels;
  final int? currentChannelIndex;

  const TvVideoPlayerScreen({
    super.key,
    required this.streamUrl,
    this.fallbackStreamUrl,
    this.httpHeaders = const {},
    required this.streamId,
    this.accountId,
    required this.title,
    this.type = VideoType.live,
    this.logo,
    this.plot,
    this.genre,
    this.year,
    this.rating,
    this.currentProgramTitle,
    this.startPosition,
    this.parentStreamId,
    this.saveSeriesSummary = true,
    this.onNextEpisode,
    this.onPrevEpisode,
    this.nextEpisodeTitle,
    this.previousEpisodeTitle,
    this.channels,
    this.currentChannelIndex,
  });

  @override
  ConsumerState<TvVideoPlayerScreen> createState() =>
      _TvVideoPlayerScreenState();
}

enum _TvPanel { channels, epg }

class _TvVideoPlayerScreenState extends ConsumerState<TvVideoPlayerScreen>
    with WidgetsBindingObserver {
  late final PlayerRepository _progressRepository;
  bool _switchingEpisode = false;
  final _episodePlayFocus = FocusNode();
  final _retryFocus = FocusNode(debugLabel: 'TvRetry');
  final _castFocus = FocusNode(debugLabel: 'TvCast');
  final _audioFocus = FocusNode(debugLabel: 'TvAudio');
  final _subtitleFocus = FocusNode(debugLabel: 'TvSubtitle');
  final _qualityFocus = FocusNode(debugLabel: 'TvQuality');
  final _speedFocus = FocusNode(debugLabel: 'TvSpeed');
  final _nextEpisodeFocus = FocusNode(debugLabel: 'TvNextEpisode');
  VideoPlayerController? _controller;
  TvSubtitleController? _subtitles;
  bool _subtitleVisible = false;
  final _focusNode = FocusNode();

  bool _showControls = true;
  bool _hasPlayed = false;
  bool _userPaused = false;
  bool _isPaused = false;
  bool _showPauseBadge = false;
  Timer? _pauseBadgeTimer;
  int _lastUiPositionSecond = -1;
  bool _modalOpen = false;
  _TvPanel? _panel;
  late final AppDatabase _sessionDb;
  StreamSubscription<List<Program>>? _epgSubscription;
  List<Program> _programs = [];
  Timer? _epgClock;
  bool _showChannelInfo = false;
  Timer? _channelInfoTimer;
  int get _activeChannelId {
    final channels = widget.channels;
    return channels != null &&
            _channelIndex >= 0 &&
            _channelIndex < channels.length
        ? channels[_channelIndex].streamId
        : widget.streamId;
  }

  String? get _programTitle {
    if (_timeshift) return null;
    final now = DateTime.now();
    for (final program in _programs) {
      if (!program.start.isAfter(now) && program.stop.isAfter(now))
        return program.title;
    }
    return _activeChannelId == widget.streamId
        ? widget.currentProgramTitle
        : null;
  }

  bool _buffering = true;
  String? _error;

  Timer? _hideTimer;
  Timer? _saveTimer;
  late final PlaybackSeekController _seek;
  int _openGeneration = 0;
  bool _disposed = false;
  bool _backgrounded = false;
  bool _resumeAfterBackground = false;
  final _controllerWork = Expando<Future<void>>();
  Timer? _bufferingTimeout;
  bool _savedInitialProgress = false;
  bool _remoteActive = false;
  bool _remoteLoading = false;
  bool _castingChromecast = false;
  Duration _remoteStartPosition = Duration.zero;
  Duration _remoteDuration = Duration.zero;
  int _remoteGeneration = 0;

  // Current stream for the active playback (changes on live channel switch).
  late String _url;
  String? _fallbackUrl;
  bool _fallbackTried = false;
  Map<String, String> _headers = const {};
  late String _title;
  String? _logo;
  late int _channelIndex;

  bool _timeshift = false;
  String? _replayTitle;
  bool _catchupAvailable = false;
  M3uCatchup? _m3uCatchup;
  int _catchupRequest = 0;
  late final Future<Account?> _sessionAccount;
  bool get _isLive => widget.type == VideoType.live;
  bool get _canSeek => !_isLive || _timeshift;

  @override
  void initState() {
    super.initState();
    final profileId =
        ref.read(activeProfileIdProvider).value ??
        ref.read(sharedPreferencesProvider).getInt('active_profile_id') ??
        1;
    _progressRepository = widget.accountId == null
        ? ref.read(playerRepositoryProvider)
        : PlayerRepository(
            ref.read(rootDatabaseProvider).forAccount(widget.accountId!),
            () => profileId,
          );

    _sessionDb = widget.accountId == null
        ? ref.read(appDatabaseProvider)
        : ref.read(rootDatabaseProvider).forAccount(widget.accountId!);
    final sessionAccountId = widget.accountId ?? _sessionDb.accountScope;
    _sessionAccount = !_isLive || sessionAccountId == null
        ? Future.value(null)
        : (_sessionDb.select(
            _sessionDb.accounts,
          )..where((a) => a.id.equals(sessionAccountId))).getSingleOrNull();
    WidgetsBinding.instance.addObserver(this);
    CastService.instance.stateNotifier.addListener(_onRemoteStateChanged);
    DlnaService.instance.stateNotifier.addListener(_onRemoteStateChanged);
    playbackActiveNotifier.value = true;
    _url = widget.streamUrl;
    _fallbackUrl = widget.fallbackStreamUrl;
    _headers = widget.httpHeaders;
    _title = widget.title;
    _logo = widget.logo;
    final channels = widget.channels;
    final requestedIndex = widget.currentChannelIndex;
    final matchingIndex =
        channels?.indexWhere((c) => c.streamId == widget.streamId) ?? -1;
    _channelIndex =
        requestedIndex != null &&
            requestedIndex >= 0 &&
            requestedIndex < (channels?.length ?? 0)
        ? requestedIndex
        : matchingIndex >= 0
        ? matchingIndex
        : 0;
    if (_isLive) {
      _watchEpg();
      unawaited(_refreshCatchup());
      _epgClock = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && (_showControls || _panel == _TvPanel.epg))
          setState(() {});
      });
    }
    _seek = PlaybackSeekController(
      position: () => _controller?.value.position ?? Duration.zero,
      duration: () => _controller?.value.duration ?? Duration.zero,
      seek: (target) async {
        final c = _controller;
        if (c != null && c.value.isInitialized)
          await _command(c, () => c.seekTo(target));
      },
      onPreview: (_) {
        if (mounted) setState(() {});
      },
      onError: () {},
    );
    WakelockPlus.enable();
    _open(_url, startAt: widget.startPosition);
    _saveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _saveProgress(),
    );
    _resetHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _resetHideTimer();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    CastService.instance.stateNotifier.removeListener(_onRemoteStateChanged);
    DlnaService.instance.stateNotifier.removeListener(_onRemoteStateChanged);
    playbackActiveNotifier.value = false;
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    ++_openGeneration;
    _saveProgress();
    _seek.dispose();
    _hideTimer?.cancel();
    _pauseBadgeTimer?.cancel();
    _epgClock?.cancel();
    _channelInfoTimer?.cancel();
    _epgSubscription?.cancel();
    _saveTimer?.cancel();
    _controller?.removeListener(_onValue);
    final retiring = _controller;
    if (retiring != null) unawaited(_retireController(retiring));
    _focusNode.dispose();
    _episodePlayFocus.dispose();
    _retryFocus.dispose();
    _castFocus.dispose();
    _audioFocus.dispose();
    _subtitleFocus.dispose();
    _qualityFocus.dispose();
    _speedFocus.dispose();
    _nextEpisodeFocus.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _command(VideoPlayerController c, Future<void> Function() run) {
    final next = (_controllerWork[c] ?? Future<void>.value()).then((_) async {
      if (!_disposed && identical(_controller, c)) await run();
    });
    final safe = next.catchError((Object _) {
      if (mounted && identical(_controller, c) && _error == null) _fail();
    });
    _controllerWork[c] = safe;
    return safe;
  }

  Future<void> _retireController(
    VideoPlayerController c, {
    bool bounded = false,
  }) async {
    // A failed IPTV connection can leave a native command/dispose pending.
    // Bound retirement so the next channel still opens on the remote.
    try {
      final work = _controllerWork[c] ?? Future<void>.value();
      if (bounded) {
        await work.timeout(const Duration(seconds: 2));
      } else {
        await work;
      }
    } catch (_) {}
    try {
      final disposal = c.dispose();
      if (bounded) {
        await disposal.timeout(const Duration(seconds: 2));
      } else {
        await disposal;
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      final resume = _resumeAfterBackground;
      _resumeAfterBackground = false;
      if (resume && c != null && c.value.isInitialized && _error == null) {
        unawaited(_command(c, c.play));
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (!_backgrounded) _resumeAfterBackground = c?.value.isPlaying ?? false;
      _backgrounded = true;
      _bufferingTimeout?.cancel();
      _bufferingTimeout = null;
      if (c != null) unawaited(_command(c, c.pause));
      _saveProgress();
    }
  }

  void _fail({
    bool timeout = false,
    bool allowFallback = true,
    String? description,
  }) {
    if (!mounted || _disposed) return;
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    _hideTimer?.cancel();
    final alternate = _fallbackUrl;
    if (allowFallback &&
        _isLive &&
        !_timeshift &&
        !_fallbackTried &&
        alternate != null &&
        alternate != _url) {
      _fallbackTried = true;
      _url = alternate;
      unawaited(_open(alternate));
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final failure = classifyTvPlaybackFailure(description);
    setState(() {
      _error = timeout
          ? l10n.connectionTimedOut
          : switch (failure) {
              TvPlaybackFailure.source => l10n.streamSourceInvalid,
              TvPlaybackFailure.decoder => l10n.streamDecoderUnsupported,
              TvPlaybackFailure.other => l10n.streamLoadFailed,
            };
      _buffering = false;
      _showControls = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed && _error != null) _retryFocus.requestFocus();
    });
    final c = _controller;
    if (c != null) unawaited(_command(c, c.pause));
  }

  VideoFormat? _formatHint(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8')) return VideoFormat.hls;
    if (path.endsWith('.mpd')) return VideoFormat.dash;
    return null; // ExoPlayer auto-detects TS / MP4 / MKV containers.
  }

  Future<void> _open(
    String url, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    final generation = ++_openGeneration;
    _seek.cancel();
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    _pauseBadgeTimer?.cancel();
    _pauseBadgeTimer = null;
    _hasPlayed = false;
    _userPaused = !autoplay && !_isLive;
    _isPaused = false;
    _showPauseBadge = false;
    _lastUiPositionSecond = -1;
    // Tear down any previous controller (channel switch / retry).
    final old = _controller;
    _controller = null;
    _subtitles = null;
    _subtitleVisible = false;
    old?.removeListener(_onValue);
    if (old != null) await _retireController(old, bounded: true);
    if (!mounted || _disposed || generation != _openGeneration) return;

    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
      });
    }

    try {
      await TvPlaybackConfig.apply(
        ref.read(settingsProvider),
        live: _isLive && !_timeshift,
      );
    } catch (_) {
      if (generation == _openGeneration) _fail(allowFallback: false);
      return;
    }
    if (!mounted || _disposed || generation != _openGeneration) return;
    _savedInitialProgress = false;
    final request = MediaRequest.parse(url, headers: _headers, nativeTv: true);
    final c = VideoPlayerController.networkUrl(
      Uri.parse(request.url),
      formatHint: _formatHint(request.url),
      // Many Xtream/IPTV servers reject unknown clients — they whitelist
      // player UAs (VLC/Kodi/etc.). media_kit/mpv sent its own accepted UA;
      // ExoPlayer's default can be refused, which shows as an endless
      // spinner (connection accepted then starved, no data). A VLC UA is the
      // most broadly whitelisted.
      httpHeaders: request.headers,
      // The route owns lifecycle and serializes commands with disposal. The
      // plugin observer would otherwise issue an untracked resume/play.
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: true,
      ),
    );
    _controller = c;
    c.addListener(_onValue);
    try {
      // Bound init so a stalled connection surfaces an error instead of
      // spinning forever (also the diagnostic signal for UA/redirect/codec
      // problems the user can report).
      await c.initialize().timeout(
        Duration(seconds: _isLive && !_timeshift ? 15 : 25),
      );
      if (!mounted ||
          _disposed ||
          generation != _openGeneration ||
          _controller != c) {
        return;
      }
      var resume = startAt;
      if (!_isLive && resume == null) {
        final saved = await _progressRepository.getProgress(
          widget.streamId,
          widget.type.name,
        );
        if (!mounted ||
            _disposed ||
            generation != _openGeneration ||
            _controller != c) {
          return;
        }
        if (saved != null && !saved.isFinished) {
          resume = Duration(milliseconds: saved.position);
        }
      }
      if (resume != null && resume > Duration.zero && _canSeek) {
        await _command(
          c,
          () =>
              c.seekTo(PlaybackSeekController.clamp(resume!, c.value.duration)),
        );
      }
      if (!mounted ||
          _disposed ||
          generation != _openGeneration ||
          _controller != c) {
        return;
      }
      if (_error != null) return;
      if (!_backgrounded && autoplay) await _command(c, c.play);
      if (!autoplay && !_isLive) _hasPlayed = true;
      unawaited(
        _bindSubtitles(c, Uri.parse(request.url).toString(), generation),
      );
      if (mounted &&
          !_disposed &&
          generation == _openGeneration &&
          _controller == c) {
        _onValue();
      }
    } catch (e) {
      // Free the stuck controller so it stops retrying in the background.
      if (_controller == c) {
        c.removeListener(_onValue);
        _controller = null;
        await _retireController(c, bounded: true);
      }
      if (mounted && !_disposed && generation == _openGeneration) {
        _fail(timeout: e is TimeoutException, description: e.toString());
      }
    }
  }

  void _onValue() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && _error == null) {
      _fail(description: v.errorDescription);
    }
    if (v.hasError || !identical(_controller, c)) return;
    if (!v.isInitialized || _error != null) return;
    if (v.isPlaying) _hasPlayed = true;
    final paused = _hasPlayed && _userPaused && !v.isPlaying && !_backgrounded;
    if (paused != _isPaused) {
      _pauseBadgeTimer?.cancel();
      _pauseBadgeTimer = null;
      setState(() {
        _isPaused = paused;
        if (paused) _showControls = true;
        if (!paused) _showPauseBadge = false;
      });
      if (paused) {
        _hideTimer?.cancel();
        if (!_isLive) {
          _pauseBadgeTimer = Timer(const Duration(seconds: 2), () {
            if (mounted && _isPaused) setState(() => _showPauseBadge = true);
          });
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.hasPrimaryFocus) {
            _episodePlayFocus.requestFocus();
          }
        });
      } else {
        _resetHideTimer();
      }
    }
    if (v.isBuffering != _buffering) setState(() => _buffering = v.isBuffering);
    if (v.isBuffering && v.isPlaying && !_backgrounded) {
      _bufferingTimeout ??= Timer(const Duration(seconds: 20), () {
        if (_controller == c && c.value.isBuffering && c.value.isPlaying) {
          _fail(timeout: true);
        }
      });
    } else {
      _bufferingTimeout?.cancel();
      _bufferingTimeout = null;
    }
    if (!_savedInitialProgress &&
        ((_isLive && v.isPlaying) ||
            (!_isLive &&
                v.position.inSeconds >= 3 &&
                v.duration.inSeconds >= 10))) {
      _savedInitialProgress = true;
      _saveProgress();
    }
    // Controller position events can be much faster than the TV needs to
    // repaint its controls. Limit whole-screen rebuilds to once per second.
    if (_showControls && v.position.inSeconds != _lastUiPositionSecond) {
      _lastUiPositionSecond = v.position.inSeconds;
      setState(() {});
    }
  }

  // ── Controls visibility ───────────────────────────────────────────────

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_error != null ||
        _modalOpen ||
        _panel != null ||
        _remoteActive ||
        _isPaused ||
        !_focusNode.hasPrimaryFocus) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isPaused && _focusNode.hasPrimaryFocus) {
        _focusNode.requestFocus();
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsBriefly() {
    if (_showChannelInfo) {
      _channelInfoTimer?.cancel();
      setState(() => _showChannelInfo = false);
    }
    if (!_showControls) setState(() => _showControls = true);
    _resetHideTimer();
  }

  // ── Playback ops ──────────────────────────────────────────────────────

  void _togglePlay() {
    if (_remoteActive) {
      if (_remoteLoading) return;
      if (_castingChromecast) {
        CastService.instance.playOrPause();
      } else {
        final dlna = DlnaService.instance;
        unawaited(dlna.state.isPlaying ? dlna.pause() : dlna.resume());
      }
      _showControlsBriefly();
      return;
    }
    if (_error != null) {
      _open(_url, startAt: _controller?.value.position);
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      _userPaused = true;
      unawaited(_command(c, c.pause));
    } else {
      _userPaused = false;
      unawaited(_command(c, c.play));
    }
    _showControlsBriefly();
  }

  void _seekBy(int seconds) {
    if (_remoteActive && _canSeek) {
      if (_remoteLoading) return;
      final current = _castingChromecast
          ? CastService.instance.state.position
          : DlnaService.instance.lastPosition ?? _remoteStartPosition;
      final target = current + Duration(seconds: seconds);
      if (_castingChromecast) {
        CastService.instance.seek(
          target < Duration.zero ? Duration.zero : target,
        );
      } else {
        unawaited(DlnaService.instance.seek(target));
      }
      _showControlsBriefly();
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized || !_canSeek) return;
    _seek.nudge(Duration(seconds: seconds));
    _showControlsBriefly();
  }

  void _channelStep(int delta) {
    if (_remoteActive) return;
    final chans = widget.channels;
    if (!_isLive || chans == null || chans.isEmpty) return;
    final next = (_channelIndex + delta) % chans.length;
    final idx = next < 0 ? next + chans.length : next;
    unawaited(_saveProgress());
    _channelIndex = idx;
    final ch = chans[idx];
    _fallbackUrl = ch.fallbackUrl;
    _fallbackTried = false;
    setState(() {
      _timeshift = false;
      _replayTitle = null;
      _catchupAvailable = false;
      _m3uCatchup = null;
      _url = ch.url;
      _headers = ch.httpHeaders;
      _title = ch.name;
      _logo = ch.logo;
      _showChannelInfo = true;
      _showControls = false;
    });
    _hideTimer?.cancel();
    _channelInfoTimer?.cancel();
    _channelInfoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showChannelInfo = false);
    });
    _focusNode.requestFocus();
    _watchEpg();
    _open(ch.url);
    unawaited(_refreshCatchup());
  }

  Future<void> _saveProgress() async {
    final c = _controller;
    final v = c?.value;
    if (!_remoteActive && (v == null || !v.isInitialized)) return;
    final remotePosition = _castingChromecast
        ? CastService.instance.lastPosition
        : DlnaService.instance.lastPosition;
    final position = _remoteActive
        ? remotePosition != null && remotePosition > Duration.zero
              ? remotePosition
              : _remoteStartPosition
        : v!.position;
    final duration = _remoteActive ? _remoteDuration : v!.duration;
    if (!_isLive && duration.inSeconds < 10) return;
    final posMs = position.inMilliseconds;
    if (posMs <= 0 && !_isLive) return;
    try {
      final channels = widget.channels;
      final sid =
          _isLive &&
              channels != null &&
              _channelIndex >= 0 &&
              _channelIndex < channels.length
          ? channels[_channelIndex].streamId
          : widget.streamId;
      final repo = _progressRepository;
      if (widget.type == VideoType.series) {
        await repo.saveEpisodeProgress(
          sid,
          posMs,
          duration.inMilliseconds,
          parentSeriesId: widget.saveSeriesSummary
              ? widget.parentStreamId
              : null,
        );
      } else {
        await repo.saveProgress(
          sid,
          widget.type.name,
          _isLive ? 1 : posMs,
          _isLive ? 100 : duration.inMilliseconds,
        );
      }
    } catch (_) {}
  }

  void _onRemoteStateChanged() {
    if (!mounted || !_remoteActive || _remoteLoading) return;
    final failed = _castingChromecast
        ? CastService.instance.state.isDisconnected ||
              CastService.instance.state.loadError != null
        : DlnaService.instance.state.isDisconnected;
    if (failed) {
      if (_castingChromecast && CastService.instance.state.loadError != null) {
        unawaited(CastService.instance.disconnect());
      }
      unawaited(_onCastStopped());
    } else {
      setState(() {});
    }
  }

  Future<void> _onCastStarted() async {
    final cast = CastService.instance;
    final dlna = DlnaService.instance;
    if (!cast.state.isConnected && !dlna.state.isConnected) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || _remoteActive) return;
    final generation = ++_remoteGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    _castingChromecast = cast.state.isConnected;
    _remoteStartPosition = c.value.position;
    _remoteDuration = c.value.duration;
    await _saveProgress();
    if (!mounted ||
        _disposed ||
        generation != _remoteGeneration ||
        !identical(_controller, c) ||
        !(_castingChromecast
            ? cast.state.isConnected
            : dlna.state.isConnected)) {
      return;
    }
    _remoteActive = true;
    _remoteLoading = true;
    _hideTimer?.cancel();
    setState(() {
      _showControls = true;
      _buffering = false;
    });

    try {
      await _command(c, c.pause);
      if (!mounted || _disposed || generation != _remoteGeneration) return;
      // Release the provider connection before LOAD. Some Xtream accounts
      // reject a second consumer even when ExoPlayer is only paused.
      c.removeListener(_onValue);
      _controller = null;
      _subtitles = null;
      _subtitleVisible = false;
      await _retireController(c);
      if (!mounted || _disposed || generation != _remoteGeneration) return;
      if (_castingChromecast) {
        if (!cast.state.isConnected) {
          await _onCastStopped();
          return;
        }
        cast.loadMedia(
          url: _url,
          title: _title,
          imageUrl: _logo,
          streamType: _isLive && !_timeshift
              ? CastStreamType.live
              : CastStreamType.buffered,
          startPosition: _remoteStartPosition,
        );
      } else {
        if (!dlna.state.isConnected) {
          await _onCastStopped();
          return;
        }
        await dlna.loadMedia(
          url: _url,
          title: _title,
          startPosition: _canSeek ? _remoteStartPosition : Duration.zero,
        );
      }
      if (!mounted || _disposed || generation != _remoteGeneration) return;
      _remoteLoading = false;
      _onRemoteStateChanged();
      if (!_remoteActive) return;
      if (!_castingChromecast) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.castConnectedTo(dlna.state.device?.displayName ?? ''),
            ),
          ),
        );
      }
      setState(() {});
    } catch (_) {
      if (!mounted || _disposed || generation != _remoteGeneration) return;
      if (_castingChromecast) {
        unawaited(cast.disconnect());
      } else {
        unawaited(dlna.disconnect());
      }
      await _onCastStopped();
      if (mounted && !_disposed) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _castingChromecast ? l10n.castFailed : l10n.dlnaConnectFailed,
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _onCastStopped() async {
    if (!_remoteActive || _disposed) return;
    unawaited(_saveProgress());
    final reportedPosition = _castingChromecast
        ? CastService.instance.lastPosition
        : DlnaService.instance.lastPosition;
    final resumeAt = _canSeek
        ? reportedPosition != null && reportedPosition > Duration.zero
              ? reportedPosition
              : _remoteStartPosition
        : null;
    _remoteActive = false;
    _remoteLoading = false;
    ++_remoteGeneration;
    if (mounted) {
      setState(() {});
      await _open(_url, startAt: resumeAt);
      if (mounted && !_disposed) {
        _showControlsBriefly();
        _castFocus.requestFocus();
      }
    }
  }

  Future<void> _switchEpisode(VoidCallback? callback) async {
    if (callback == null || _switchingEpisode) return;
    _switchingEpisode = true;
    await _saveProgress();
    if (mounted && !_disposed) callback();
  }

  void _watchEpg() {
    _epgSubscription?.cancel();
    _programs = [];
    final id = _activeChannelId;
    final p = _sessionDb.programs;
    _epgSubscription =
        (_sessionDb.select(p)
              ..where(
                (p) =>
                    p.channelId.equals(id) &
                    p.stop.isBiggerThanValue(
                      DateTime.now().subtract(const Duration(days: 5)),
                    ),
              )
              ..orderBy([(p) => OrderingTerm(expression: p.start)]))
            .watch()
            .listen((programs) {
              if (!mounted || id != _activeChannelId) return;
              _programs = programs;
              if (_showControls || _showChannelInfo || _panel == _TvPanel.epg) {
                setState(() {});
              }
            }, onError: (Object _) {});
  }

  Future<void> _refreshCatchup() async {
    final request = ++_catchupRequest;
    final channelId = _activeChannelId;
    try {
      final account = await _sessionAccount;
      M3uCatchup? m3u;
      var available =
          account?.type == 'xtream' &&
          account?.username != null &&
          account?.password != null;
      if (account?.type == 'm3u') {
        final row =
            await (_sessionDb.select(_sessionDb.channels)..where(
                  (c) => c.streamId.equals(channelId) & c.type.equals('live'),
                ))
                .getSingleOrNull();
        m3u = M3uCatchup.decode(row?.catchupMetadata);
        available = m3u != null;
      }
      if (!mounted ||
          _disposed ||
          request != _catchupRequest ||
          channelId != _activeChannelId)
        return;
      setState(() {
        _m3uCatchup = m3u;
        _catchupAvailable = available;
      });
    } catch (_) {
      if (mounted && !_disposed && request == _catchupRequest) {
        setState(() {
          _m3uCatchup = null;
          _catchupAvailable = false;
        });
      }
    }
  }

  Future<void> _startTimeshift(Program program) async {
    final now = DateTime.now();
    if (!_isLive ||
        program.channelId != _activeChannelId ||
        !program.stop.isBefore(now))
      return;
    final channelId = _activeChannelId;
    final generation = _openGeneration;
    final account = await _sessionAccount;
    if (!mounted ||
        _disposed ||
        generation != _openGeneration ||
        channelId != _activeChannelId)
      return;
    final m3u = _m3uCatchup;
    final maxDays = account?.type == 'm3u' ? m3u?.days : 5;
    if (maxDays == null ||
        now.difference(program.stop) > Duration(days: maxDays))
      return;
    String url;
    if (account?.type == 'm3u' && m3u != null) {
      final channels = widget.channels;
      final liveUrl =
          channels != null &&
              _channelIndex >= 0 &&
              _channelIndex < channels.length
          ? channels[_channelIndex].url
          : widget.streamUrl;
      final replay = m3u.buildUrl(
        liveUrl: liveUrl,
        start: program.start,
        end: program.stop,
      );
      if (replay == null) return;
      url = replay.toString();
    } else if (account?.type == 'xtream' &&
        account?.username != null &&
        account?.password != null) {
      url = StreamUrlBuilder.timeshift(
        account!.url,
        account.username!,
        account.password!,
        channelId,
        start: program.start,
        duration: program.stop.difference(program.start),
      );
    } else {
      return;
    }
    _closePanel();
    setState(() {
      _timeshift = true;
      _replayTitle = program.title;
      _url = url;
    });
    await _open(url);
  }

  void _returnToLive() {
    if (!_timeshift) return;
    final channels = widget.channels;
    if (channels != null && channels.isNotEmpty) {
      _channelStep(0);
      return;
    }
    setState(() {
      _timeshift = false;
      _replayTitle = null;
      _url = widget.streamUrl;
      _fallbackUrl = widget.fallbackStreamUrl;
      _fallbackTried = false;
    });
    _open(_url);
    _showControlsBriefly();
  }

  void _openPanel(_TvPanel panel) {
    if (!_isLive || _modalOpen) return;
    _hideTimer?.cancel();
    setState(() {
      _panel = panel;
      _showControls = true;
    });
    if (panel == _TvPanel.epg) {
      final account = widget.accountId ?? _sessionDb.accountScope;
      if (account != null) {
        final id = _activeChannelId;
        final repo = ref.read(contentRepositoryProvider).forAccount(account);
        unawaited(
          ref
              .read(epgRequestGateProvider)
              .request(account, id, () => repo.syncChannelEpg(account, '$id')),
        );
      }
    }
  }

  void _closePanel({bool showControls = true}) {
    if (!mounted || _panel == null) return;
    setState(() => _panel = null);
    if (_error != null) {
      _retryFocus.requestFocus();
      return;
    }
    if (showControls) {
      _showControlsBriefly();
      _episodePlayFocus.requestFocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _bindSubtitles(
    VideoPlayerController c,
    String url,
    int generation,
  ) async {
    try {
      final subtitles = await TvSubtitleController.resolve(url);
      if (!mounted ||
          generation != _openGeneration ||
          c != _controller ||
          subtitles == null)
        return;
      final tracks = await subtitles.tracks();
      if (!mounted || generation != _openGeneration || c != _controller) return;
      final settings = ref.read(settingsProvider);
      final match = findBestSubtitleTrack(
        tracks: [
          for (var i = 0; i < tracks.length; i++)
            (
              id: '$i',
              language: tracks[i]['language'] as String?,
              title: tracks[i]['label'] as String?,
            ),
        ],
        wantLanguage: settings.lastPlayerSubtitleLanguage,
        wantTitle: settings.lastPlayerSubtitleTitle,
      );
      if (match != null) await subtitles.select(tracks[int.parse(match.id)]);
      if (!mounted || generation != _openGeneration || c != _controller) return;
      setState(() {
        _subtitles = subtitles;
        _subtitleVisible =
            match != null || tracks.any((t) => t['selected'] == true);
      });
    } catch (_) {
      /* Optional subtitles never prevent video playback. */
    }
  }

  Future<void> _chooseSubtitles() async {
    if (_modalOpen) return;
    final generation = _openGeneration;
    var subtitles = _subtitles;
    if (subtitles == null) {
      try {
        final request = MediaRequest.parse(
          _url,
          headers: _headers,
          nativeTv: true,
        );
        subtitles = await TvSubtitleController.resolve(request.url);
      } catch (_) {}
      if (!mounted || generation != _openGeneration) return;
      if (subtitles == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.subtitleNotFound),
          ),
        );
        return;
      }
      setState(() => _subtitles = subtitles);
    }
    _modalOpen = true;
    _hideTimer?.cancel();
    final l10n = AppLocalizations.of(context)!;
    try {
      final tracks = await subtitles.tracks();
      if (!mounted || generation != _openGeneration) return;
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l10n.subtitle),
          children: [
            ListTile(
              autofocus: !tracks.any((t) => t['selected'] == true),
              leading: const Icon(Icons.subtitles_off),
              title: Text(l10n.profileGroupClear),
              onTap: () => Navigator.of(dialogContext).pop(-1),
            ),
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                autofocus: tracks[i]['selected'] == true,
                selected: tracks[i]['selected'] == true,
                title: Text(
                  [tracks[i]['label'], tracks[i]['language']]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · ')
                          .isEmpty
                      ? '${l10n.subtitle} ${i + 1}'
                      : [tracks[i]['label'], tracks[i]['language']]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                ),
                onTap: () => Navigator.of(dialogContext).pop(i),
              ),
          ],
        ),
      );
      if (selected != null && mounted && generation == _openGeneration) {
        await subtitles.select(selected < 0 ? null : tracks[selected]);
        if (!mounted || generation != _openGeneration) return;
        setState(() => _subtitleVisible = selected >= 0);
        final settings = ref.read(settingsProvider);
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              selected < 0
                  ? settings.copyWith(clearLastPlayerSubtitleLanguage: true)
                  : settings.copyWith(
                      lastPlayerSubtitleLanguage:
                          tracks[selected]['language'] as String? ?? '',
                      lastPlayerSubtitleTitle:
                          tracks[selected]['label'] as String? ?? '',
                    ),
            );
      }
    } catch (_) {
      if (mounted && generation == _openGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.subtitle}: ${l10n.error}')),
        );
      }
    } finally {
      _modalOpen = false;
      if (mounted && generation == _openGeneration) {
        _showControlsBriefly();
        _subtitleFocus.requestFocus();
      }
    }
  }

  Future<void> _chooseQuality() async {
    final c = _controller;
    if (_modalOpen || c == null || !c.value.isInitialized) return;
    _modalOpen = true;
    _hideTimer?.cancel();
    var expectedGeneration = _openGeneration;
    final l10n = AppLocalizations.of(context)!;
    final current = ref.read(settingsProvider).streamQuality;
    try {
      final selected = await showDialog<StreamQuality>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(l10n.streamQuality),
          children: [
            for (final quality in StreamQuality.values)
              ListTile(
                autofocus: quality == current,
                onTap: () => Navigator.of(dialogContext).pop(quality),
                title: Text(switch (quality) {
                  StreamQuality.auto => l10n.qualityAuto,
                  StreamQuality.high => l10n.qualityHigh,
                  StreamQuality.medium => l10n.qualityMedium,
                  StreamQuality.low => l10n.qualityLow,
                }),
              ),
          ],
        ),
      );
      if (!mounted ||
          expectedGeneration != _openGeneration ||
          selected == null ||
          selected == current)
        return;
      final wasPlaying = c.value.isPlaying;
      final position = c.value.position;
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            ref.read(settingsProvider).copyWith(streamQuality: selected),
          );
      expectedGeneration++;
      await _open(
        _url,
        startAt: _canSeek ? position : null,
        autoplay: wasPlaying,
      );
    } finally {
      _modalOpen = false;
      if (mounted && expectedGeneration == _openGeneration) {
        _showControlsBriefly();
        _qualityFocus.requestFocus();
      }
    }
  }

  Future<void> _chooseAudioTrack() async {
    final controller = _controller;
    if (_modalOpen || controller == null || !controller.value.isInitialized)
      return;
    _modalOpen = true;
    _hideTimer?.cancel();
    final generation = _openGeneration;
    final l10n = AppLocalizations.of(context)!;
    try {
      final tracks = await controller.getAudioTracks().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted ||
          generation != _openGeneration ||
          controller != _controller)
        return;
      final selected = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.audioTrack),
          content: SizedBox(
            width: 420,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final label = [track.label, track.language, track.codec]
                    .whereType<String>()
                    .where((v) => v.trim().isNotEmpty)
                    .join(' · ');
                return ListTile(
                  autofocus:
                      track.isSelected ||
                      (!tracks.any((t) => t.isSelected) && index == 0),
                  selected: track.isSelected,
                  leading: Icon(
                    track.isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(
                    label.isEmpty ? '${l10n.audioTrack} ${index + 1}' : label,
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(track.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              autofocus: tracks.isEmpty,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
      if (selected != null &&
          mounted &&
          generation == _openGeneration &&
          controller == _controller) {
        await controller
            .selectAudioTrack(selected)
            .timeout(const Duration(seconds: 5));
        if (mounted && generation == _openGeneration) {
          final track = tracks.firstWhere((t) => t.id == selected);
          ref
              .read(settingsProvider.notifier)
              .updateSettings(
                ref
                    .read(settingsProvider)
                    .copyWith(
                      lastPlayerAudioLanguage: track.language ?? '',
                      lastPlayerAudioTitle: track.label ?? '',
                    ),
              );
        }
      }
    } catch (_) {
      if (mounted && generation == _openGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.audioTrack}: ${l10n.error}')),
        );
      }
    } finally {
      _modalOpen = false;
      if (mounted && generation == _openGeneration) {
        _showControlsBriefly();
        _audioFocus.requestFocus();
      }
    }
  }

  Future<void> _chooseSpeed() async {
    final controller = _controller;
    if (_modalOpen || controller == null || !controller.value.isInitialized) {
      return;
    }
    _modalOpen = true;
    _hideTimer?.cancel();
    final generation = _openGeneration;
    try {
      final selected = await showDialog<double>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(AppLocalizations.of(context)!.playbackSpeed),
          children: [
            for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              ListTile(
                autofocus: speed == controller.value.playbackSpeed,
                selected: speed == controller.value.playbackSpeed,
                title: Text('${speed}x'),
                onTap: () => Navigator.of(dialogContext).pop(speed),
              ),
          ],
        ),
      );
      if (selected != null &&
          mounted &&
          generation == _openGeneration &&
          controller == _controller) {
        await _command(controller, () => controller.setPlaybackSpeed(selected));
      }
    } finally {
      _modalOpen = false;
      if (mounted && generation == _openGeneration) {
        _showControlsBriefly();
        _speedFocus.requestFocus();
      }
    }
  }

  // ── Keys ──────────────────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (_panel != null) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      if (mounted) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext &&
        widget.onNextEpisode != null) {
      _switchEpisode(widget.onNextEpisode);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious &&
        widget.onPrevEpisode != null) {
      _switchEpisode(widget.onPrevEpisode);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (_isLive &&
        (k == LogicalKeyboardKey.keyC || k == LogicalKeyboardKey.keyG)) {
      _openPanel(
        k == LogicalKeyboardKey.keyC ? _TvPanel.channels : _TvPanel.epg,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.contextMenu || k == LogicalKeyboardKey.info) {
      _showControlsBriefly();
      _episodePlayFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // A failed channel focuses Retry. Keep channel and guide navigation
    // available so one bad source never traps the remote in the player.
    if (_error != null &&
        _isLive &&
        !_timeshift &&
        widget.channels?.isNotEmpty == true) {
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        _channelStep(k == LogicalKeyboardKey.arrowUp ? -1 : 1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        _openPanel(
          k == LogicalKeyboardKey.arrowLeft ? _TvPanel.channels : _TvPanel.epg,
        );
        return KeyEventResult.handled;
      }
    }
    // Let focused episode buttons handle activation and directional traversal.
    if (!_focusNode.hasPrimaryFocus && (_showControls || _error != null)) {
      _resetHideTimer();
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
      if (_isLive) {
        _showControlsBriefly();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _episodePlayFocus.requestFocus();
        });
      } else {
        _togglePlay();
      }
      return KeyEventResult.handled;
    }
    if (_remoteActive) {
      if (k == LogicalKeyboardKey.arrowLeft && _canSeek) _seekBy(-10);
      if (k == LogicalKeyboardKey.arrowRight && _canSeek) _seekBy(10);
      if (k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.arrowDown) {
        _showControlsBriefly();
        _castFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (_isLive && !_timeshift) {
        _openPanel(_TvPanel.channels);
      } else {
        _seekBy(-10);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_isLive && !_timeshift) {
        _openPanel(_TvPanel.epg);
      } else {
        _seekBy(10);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_isLive) {
        _channelStep(-1);
      } else {
        _showControlsBriefly();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _episodePlayFocus.requestFocus();
        });
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_isLive) {
        _channelStep(1);
      } else {
        _showControlsBriefly();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _audioFocus.requestFocus();
        });
      }
      return KeyEventResult.handled;
    }
    _showControlsBriefly();
    return KeyEventResult.ignored;
  }

  // ── UI ────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Keep preferences alive across asynchronous controller replacement.
    final settings = ref.watch(settingsProvider);
    final subtitleColor =
        0xff000000 |
        ((int.tryParse(
                  settings.subtitleColor.replaceFirst('#', ''),
                  radix: 16,
                ) ??
                0xffffff) &
            0xffffff);
    final c = _controller;
    final v = c?.value;
    return PopScope(
      canPop: _panel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closePanel();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          onTap: _showControlsBriefly,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Video
                if (!_remoteActive && v != null && v.isInitialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(c!),
                          if (_subtitles != null && _subtitleVisible)
                            IgnorePointer(
                              child: ExcludeFocus(
                                child: AndroidView(
                                  key: ValueKey(_subtitles!.playerId),
                                  viewType: 'com.lifeostv.lifeostv/subtitles',
                                  creationParamsCodec:
                                      const StandardMessageCodec(),
                                  creationParams: {
                                    'playerId': _subtitles!.playerId,
                                    'fontFraction':
                                        settings.subtitleFontSize / 1080.0,
                                    'color': subtitleColor,
                                    'bold': settings.subtitleBold,
                                    'background':
                                        settings.subtitleBackgroundEnabled,
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Buffering
                if (_remoteActive)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cast_connected,
                          color: AppColors.primary,
                          size: 64,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)!.castingBanner(
                            _castingChromecast
                                ? CastService.instance.state.device?.name ?? ''
                                : DlnaService
                                          .instance
                                          .state
                                          .device
                                          ?.displayName ??
                                      '',
                          ),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                if (_buffering && _error == null && !_remoteActive)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),

                // Controls stay behind the retry button.
                AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !_showControls || _panel != null,
                    child: ExcludeFocus(
                      excluding:
                          !_showControls || _error != null || _panel != null,
                      child: _buildControls(v),
                    ),
                  ),
                ),

                if (_showChannelInfo && _panel == null && !_showControls)
                  _buildChannelInfoOverlay(),

                // Error
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white54,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            focusNode: _retryFocus,
                            onPressed: _togglePlay,
                            icon: const Icon(Icons.refresh),
                            label: Text(AppLocalizations.of(context)!.retry),
                          ),
                          if (_timeshift)
                            TextButton.icon(
                              key: const ValueKey('tv-error-return-live'),
                              onPressed: _returnToLive,
                              icon: const Icon(Icons.live_tv),
                              label: Text(AppLocalizations.of(context)!.liveTV),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (_panel == _TvPanel.channels)
                  ChannelListOverlay(
                    channels:
                        widget.channels ??
                        [
                          PlayerChannel(
                            streamId: widget.streamId,
                            name: _title,
                            url: _url,
                            httpHeaders: _headers,
                          ),
                        ],
                    currentChannelIndex: _channelIndex,
                    categoryNames: {
                      for (final c in widget.channels ?? <PlayerChannel>[])
                        if (c.categoryId != null && c.categoryName != null)
                          c.categoryId!: c.categoryName!,
                    },
                    onChannelSelected: (index) {
                      if (_timeshift && index == _channelIndex) {
                        _returnToLive();
                      } else if (index != _channelIndex) {
                        _channelStep(index - _channelIndex);
                      } else {
                        _closePanel();
                        return;
                      }
                      _closePanel(showControls: false);
                    },
                    onClose: _closePanel,
                  ),
                if (_panel == _TvPanel.epg)
                  EpgOverlay(
                    programs: _programs,
                    onCatchUp: _catchupAvailable ? _startTimeshift : null,
                    channelName: _title,
                    channelLogo: _logo,
                    onClose: _closePanel,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerValue? v) {
    final pos = _remoteActive
        ? (_castingChromecast
              ? CastService.instance.state.position
              : DlnaService.instance.lastPosition ?? _remoteStartPosition)
        : _seek.preview ?? v?.position ?? Duration.zero;
    final dur = _remoteActive && _castingChromecast
        ? CastService.instance.state.duration
        : v?.duration ?? Duration.zero;
    final playing = _remoteActive
        ? (_castingChromecast
              ? CastService.instance.state.isPlaying
              : DlnaService.instance.state.isPlaying)
        : v?.isPlaying ?? false;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.75),
          ],
          stops: const [0, 0.4, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
        child: Column(
          children: [
            // Top: back + logo + title
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                if (_logo != null && _logo!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: _logo!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      memCacheWidth: 120,
                      errorWidget: (_, _, _) => const SizedBox(width: 40),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replayTitle ?? _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_programTitle != null && _programTitle!.isNotEmpty)
                        Text(
                          _programTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (v?.isInitialized == true || _remoteActive)
                  CastButton(
                    key: const ValueKey('tv-cast'),
                    focusNode: _castFocus,
                    enabled: !_remoteLoading,
                    onCastStarted: () => unawaited(_onCastStarted()),
                    onCastStopped: () => unawaited(_onCastStopped()),
                    onPickerVisibilityChanged: (open) {
                      _modalOpen = open;
                      if (open) {
                        _hideTimer?.cancel();
                      } else {
                        _showControlsBriefly();
                      }
                    },
                  ),
                if (_isLive && !_timeshift)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            if (_showPauseBadge && !_isLive) ...[
              _buildPauseInfoBadge(pos, dur),
              const SizedBox(height: 12),
            ],
            // Bottom: playback progress for seekable content.
            if (_canSeek && dur.inSeconds > 0) ...[
              Row(
                children: [
                  Text(
                    _fmt(pos),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: dur.inMilliseconds > 0
                              ? (pos.inMilliseconds / dur.inMilliseconds).clamp(
                                  0.0,
                                  1.0,
                                )
                              : 0,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _fmt(dur),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.onPrevEpisode != null)
                  _actionButton(
                    key: const ValueKey('previous-episode'),
                    icon: Icons.skip_previous,
                    label: widget.previousEpisodeTitle,
                    onPressed: () => _switchEpisode(widget.onPrevEpisode),
                  ),
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _castFocus.requestFocus(),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _audioFocus.requestFocus(),
                  },
                  child: _actionButton(
                    key: const ValueKey('episode-play-pause'),
                    icon: playing ? Icons.pause : Icons.play_arrow,
                    label: AppLocalizations.of(context)!.play,
                    focusNode: _episodePlayFocus,
                    primary: true,
                    onPressed: _togglePlay,
                  ),
                ),
                if (_canSeek && !_remoteActive) ...[
                  _actionButton(
                    key: const ValueKey('tv-rewind'),
                    icon: Icons.replay_10,
                    onPressed: () => _seekBy(-10),
                  ),
                  _actionButton(
                    key: const ValueKey('tv-forward'),
                    icon: Icons.forward_10,
                    onPressed: () => _seekBy(10),
                  ),
                ],
                if (widget.onNextEpisode != null)
                  _actionButton(
                    key: const ValueKey('next-episode'),
                    icon: Icons.skip_next,
                    focusNode: _nextEpisodeFocus,
                    label:
                        widget.nextEpisodeTitle ??
                        AppLocalizations.of(context)!.nextEpisode,
                    onPressed: () => _switchEpisode(widget.onNextEpisode),
                  ),
                const Spacer(),
                if (!_remoteActive) ...[
                  _actionButton(
                    key: const ValueKey('tv-audio-tracks'),
                    icon: Icons.audiotrack,
                    label: AppLocalizations.of(context)!.audioTrack,
                    focusNode: _audioFocus,
                    onPressed: v?.isInitialized == true
                        ? _chooseAudioTrack
                        : null,
                  ),
                  _actionButton(
                    key: const ValueKey('tv-subtitles'),
                    icon: Icons.subtitles_outlined,
                    label: AppLocalizations.of(context)!.subtitle,
                    focusNode: _subtitleFocus,
                    onPressed: v?.isInitialized == true
                        ? _chooseSubtitles
                        : null,
                  ),
                  _actionButton(
                    key: const ValueKey('tv-quality'),
                    icon: Icons.high_quality_outlined,
                    label: AppLocalizations.of(context)!.streamQuality,
                    focusNode: _qualityFocus,
                    onPressed: v?.isInitialized == true ? _chooseQuality : null,
                  ),
                  if (!_isLive)
                    _actionButton(
                      key: const ValueKey('tv-speed'),
                      icon: Icons.speed,
                      label: AppLocalizations.of(context)!.playbackSpeed,
                      focusNode: _speedFocus,
                      onPressed: v?.isInitialized == true ? _chooseSpeed : null,
                    ),
                  if (_isLive)
                    _actionButton(
                      key: const ValueKey('tv-channel-list'),
                      icon: Icons.list,
                      label: AppLocalizations.of(context)!.channelList,
                      onPressed: () => _openPanel(_TvPanel.channels),
                    ),
                  if (_timeshift)
                    _actionButton(
                      key: const ValueKey('tv-return-live'),
                      icon: Icons.live_tv,
                      label: AppLocalizations.of(context)!.liveTV,
                      onPressed: _returnToLive,
                    ),
                  if (_isLive)
                    _actionButton(
                      key: const ValueKey('tv-program-guide'),
                      icon: Icons.calendar_month,
                      label: AppLocalizations.of(context)!.programGuide,
                      onPressed: () => _openPanel(_TvPanel.epg),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    Key? key,
    required IconData icon,
    String? label,
    required VoidCallback? onPressed,
    FocusNode? focusNode,
    bool primary = false,
  }) {
    return TvPlayerActionButton(
      key: key,
      icon: icon,
      label: label,
      onPressed: onPressed,
      focusNode: focusNode,
      primary: primary,
    );
  }

  Widget _buildChannelInfoOverlay() {
    final now = DateTime.now();
    Program? current;
    Program? next;
    for (final program in _programs) {
      if (!program.start.isAfter(now) && program.stop.isAfter(now)) {
        current = program;
      } else if (program.start.isAfter(now) && next == null) {
        next = program;
      }
      if (current != null && next != null) break;
    }
    final total = current?.stop.difference(current.start).inSeconds ?? 0;
    final elapsed = current == null
        ? 0
        : now.difference(current.start).inSeconds;
    final progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
    final channels = widget.channels;
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      key: const ValueKey('tv-channel-info'),
      left: 24,
      right: 24,
      bottom: 24,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: const Color(0xE6101118),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _logo != null && _logo!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _logo!,
                        width: 68,
                        height: 68,
                        fit: BoxFit.contain,
                        memCacheWidth: 204,
                        errorWidget: (_, _, _) => const Icon(
                          Icons.tv,
                          size: 52,
                          color: Colors.white54,
                        ),
                      )
                    : const SizedBox(
                        width: 68,
                        height: 68,
                        child: Icon(Icons.tv, size: 52, color: Colors.white54),
                      ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'LIVE${channels == null ? '' : '  ${_channelIndex + 1}/${channels.length}'}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (current != null) ...[
                      Text(
                        '${DateFormat('HH:mm').format(current.start)}–${DateFormat('HH:mm').format(current.stop)}  ${current.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.primary,
                        ),
                      ),
                    ] else
                      Text(
                        l10n.noProgramGuide,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    if (next != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        '${l10n.upNextLabel} ${DateFormat('HH:mm').format(next.start)}  ${next.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.keyboard_arrow_up, color: Colors.white54),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPauseInfoBadge(Duration position, Duration duration) {
    final l10n = AppLocalizations.of(context)!;
    final remaining = duration - position;
    return Align(
      key: const ValueKey('tv-pause-info'),
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xEB101014),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_logo != null && _logo!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: _logo!,
                    width: 70,
                    height: 105,
                    fit: BoxFit.cover,
                    memCacheWidth: 210,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.year != null ||
                        widget.rating != null ||
                        widget.genre != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          widget.year,
                          if (widget.rating != null && widget.rating! > 0)
                            '★ ${widget.rating!.toStringAsFixed(1)}',
                          widget.genre,
                        ].whereType<String>().join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (widget.plot != null && widget.plot!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.plot!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (duration > Duration.zero) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_fmt(position)} / ${_fmt(duration)}'
                        '${remaining > Duration.zero ? '  (${_fmt(remaining)} ${l10n.remaining})' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
