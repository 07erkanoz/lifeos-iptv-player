import 'package:lifeostv/data/repositories/profile_repository.dart' show activeProfileIdProvider;
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/presentation/controllers/tv_playback_config.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/core/playback_signal.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/controllers/playback_seek_controller.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart'
    show VideoType, PlayerChannel;

/// Android-TV-only video player backed by ExoPlayer (via `video_player`).
///
/// Why a separate screen: media_kit/mpv renders every frame into a Flutter
/// GL texture and runs its shader chain — smooth on desktop/mobile but a
/// stutter ceiling on weak Android-TV GPUs. ExoPlayer decodes via MediaCodec
/// straight to a Surface (the efficient Android path, like TiViMate). This
/// screen is routed ONLY when `Android && PlatformHelper.isTV`; every other
/// platform keeps the full media_kit [VideoPlayerScreen] untouched.
///
/// Milestone 1: core playback + D-pad controls (OK = play/pause, ←/→ seek on
/// VOD, ↑/↓ channel switch on live), resume-position save, buffering/error
/// states. Channel list / EPG / subtitle / cast overlays come next.
class TvVideoPlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final int streamId;
  final int? accountId;
  final String title;
  final VideoType type;
  final String? logo;
  final String? currentProgramTitle;
  final Duration? startPosition;
  final int? parentStreamId;
  final List<PlayerChannel>? channels;
  final int? currentChannelIndex;

  const TvVideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.streamId,
    this.accountId,
    required this.title,
    this.type = VideoType.live,
    this.logo,
    this.currentProgramTitle,
    this.startPosition,
    this.parentStreamId,
    this.channels,
    this.currentChannelIndex,
  });

  @override
  ConsumerState<TvVideoPlayerScreen> createState() =>
      _TvVideoPlayerScreenState();
}

class _TvVideoPlayerScreenState extends ConsumerState<TvVideoPlayerScreen>
    with WidgetsBindingObserver {
  late final PlayerRepository _progressRepository;
  VideoPlayerController? _controller;
  final _focusNode = FocusNode();

  bool _showControls = true;
  bool _buffering = true;
  String? _error;

  Timer? _hideTimer;
  Timer? _saveTimer;
  late final PlaybackSeekController _seek;
  int _openGeneration = 0;
  bool _disposed = false;
  bool _backgrounded = false;
  Timer? _bufferingTimeout;
  bool _savedInitialProgress = false;

  // Current stream for the active playback (changes on live channel switch).
  late String _url;
  late String _title;
  String? _logo;
  late int _channelIndex;

  bool get _isLive => widget.type == VideoType.live;

  @override
  void initState() {
    super.initState();
    final profileId = ref.read(activeProfileIdProvider).value ??
        ref.read(sharedPreferencesProvider).getInt('active_profile_id') ?? 1;
    _progressRepository = widget.accountId == null
        ? ref.read(playerRepositoryProvider)
        : PlayerRepository(ref.read(rootDatabaseProvider).forAccount(widget.accountId!), () => profileId);

    WidgetsBinding.instance.addObserver(this);
    playbackActiveNotifier.value = true;
    _url = widget.streamUrl;
    _title = widget.title;
    _logo = widget.logo;
    _channelIndex = widget.currentChannelIndex ?? 0;
    _seek = PlaybackSeekController(
      position: () => _controller?.value.position ?? Duration.zero,
      duration: () => _controller?.value.duration ?? Duration.zero,
      seek: (target) async {
        final c = _controller;
        if (c != null && c.value.isInitialized) await c.seekTo(target);
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
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    playbackActiveNotifier.value = false;
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    ++_openGeneration;
    _saveProgress();
    _seek.dispose();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _controller?.removeListener(_onValue);
    _controller?.dispose();
    _focusNode.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _backgrounded = false;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      _bufferingTimeout?.cancel();
      _bufferingTimeout = null;
      unawaited(
        _controller?.pause().catchError((Object _) {}) ?? Future.value(),
      );
      _saveProgress();
    }
  }

  void _fail({bool timeout = false}) {
    if (!mounted || _disposed) return;
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    _hideTimer?.cancel();
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _error = timeout ? l10n.connectionTimedOut : l10n.streamLoadFailed;
      _buffering = false;
      _showControls = true;
    });
    unawaited(_controller?.pause().catchError((Object _) {}) ?? Future.value());
  }

  VideoFormat? _formatHint(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    if (path.endsWith('.m3u8')) return VideoFormat.hls;
    if (path.endsWith('.mpd')) return VideoFormat.dash;
    return null; // ExoPlayer auto-detects TS / MP4 / MKV containers.
  }

  Future<void> _open(String url, {Duration? startAt}) async {
    if (_disposed) return;
    final generation = ++_openGeneration;
    _seek.cancel();
    _bufferingTimeout?.cancel();
    _bufferingTimeout = null;
    // Tear down any previous controller (channel switch / retry).
    final old = _controller;
    _controller = null;
    old?.removeListener(_onValue);
    await old?.dispose().catchError((Object _) {});
    if (!mounted || _disposed || generation != _openGeneration) return;

    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
      });
    }

    try {
      await TvPlaybackConfig.apply(ref.read(settingsProvider), live: _isLive);
    } catch (_) {
      if (generation == _openGeneration) _fail();
      return;
    }
    if (!mounted || _disposed || generation != _openGeneration) return;
    _savedInitialProgress = false;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: _formatHint(url),
      // Many Xtream/IPTV servers reject unknown clients — they whitelist
      // player UAs (VLC/Kodi/etc.). media_kit/mpv sent its own accepted UA;
      // ExoPlayer's default can be refused, which shows as an endless
      // spinner (connection accepted then starved, no data). A VLC UA is the
      // most broadly whitelisted.
      httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _controller = c;
    c.addListener(_onValue);
    try {
      // Bound init so a stalled connection surfaces an error instead of
      // spinning forever (also the diagnostic signal for UA/redirect/codec
      // problems the user can report).
      await c.initialize().timeout(const Duration(seconds: 25));
      if (!mounted ||
          _disposed ||
          generation != _openGeneration ||
          _controller != c) {
        return;
      }
      var resume = startAt;
      if (!_isLive && resume == null) {
        final saved = await _progressRepository
            .getProgress(widget.streamId, widget.type.name);
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
      if (resume != null && resume > Duration.zero && !_isLive) {
        await c.seekTo(PlaybackSeekController.clamp(resume, c.value.duration));
      }
      if (!mounted ||
          _disposed ||
          generation != _openGeneration ||
          _controller != c) {
        return;
      }
      if (_error != null) return;
      if (!_backgrounded) await c.play();
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
        await c.dispose().catchError((Object _) {});
      }
      if (mounted && !_disposed && generation == _openGeneration) {
        _fail(timeout: e is TimeoutException);
      }
    }
  }

  void _onValue() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && _error == null) _fail();
    if (!v.isInitialized || _error != null) return;
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
    if (!_isLive &&
        !_savedInitialProgress &&
        v.position.inSeconds >= 3 &&
        v.duration.inSeconds >= 10) {
      _savedInitialProgress = true;
      _saveProgress();
    }
    // Keep the bottom-bar position/duration live while controls are shown.
    if (_showControls) setState(() {});
  }

  // ── Controls visibility ───────────────────────────────────────────────

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_error != null) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _showControlsBriefly() {
    if (!_showControls) setState(() => _showControls = true);
    _resetHideTimer();
  }

  // ── Playback ops ──────────────────────────────────────────────────────

  void _togglePlay() {
    if (_error != null) {
      _open(_url, startAt: _controller?.value.position);
      return;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _showControlsBriefly();
  }

  void _seekBy(int seconds) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isLive) return;
    _seek.nudge(Duration(seconds: seconds));
    _showControlsBriefly();
  }

  void _channelStep(int delta) {
    final chans = widget.channels;
    if (!_isLive || chans == null || chans.isEmpty) return;
    final next = (_channelIndex + delta) % chans.length;
    final idx = next < 0 ? next + chans.length : next;
    _channelIndex = idx;
    final ch = chans[idx];
    setState(() {
      _url = ch.url;
      _title = ch.name;
      _logo = ch.logo;
    });
    _open(ch.url);
    _showControlsBriefly();
  }

  Future<void> _saveProgress() async {
    final c = _controller;
    if (c == null || _isLive) return;
    final v = c.value;
    if (!v.isInitialized || v.duration.inSeconds < 10) return;
    final posMs = v.position.inMilliseconds;
    if (posMs <= 0) return;
    try {
      final sid = widget.streamId;
      final repo = _progressRepository;
      await repo.saveProgress(
        sid,
        widget.type.name,
        posMs,
        v.duration.inMilliseconds,
      );
      if (widget.type == VideoType.series &&
          widget.parentStreamId != null &&
          widget.parentStreamId != sid) {
        await repo.saveProgress(
          widget.parentStreamId!,
          widget.type.name,
          posMs,
          v.duration.inMilliseconds,
        );
      }
    } catch (_) {}
  }

  // ── Keys ──────────────────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack) {
      if (mounted) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_isLive) {
        _channelStep(-1);
      } else {
        _showControlsBriefly();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_isLive) {
        _channelStep(1);
      } else {
        _showControlsBriefly();
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
    final c = _controller;
    final v = c?.value;
    return PopScope(
      canPop: true,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          onTap: _showControlsBriefly,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video
                if (v != null && v.isInitialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                      child: VideoPlayer(c!),
                    ),
                  ),

                // Buffering
                if (_buffering && _error == null)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),

                // Controls stay behind the retry button.
                AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControls(v),
                  ),
                ),

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
                            onPressed: _togglePlay,
                            icon: const Icon(Icons.refresh),
                            label: Text(AppLocalizations.of(context)!.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerValue? v) {
    final pos = _seek.preview ?? v?.position ?? Duration.zero;
    final dur = v?.duration ?? Duration.zero;
    final playing = v?.isPlaying ?? false;
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
                const Icon(Icons.arrow_back, color: Colors.white, size: 24),
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
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.currentProgramTitle != null &&
                          widget.currentProgramTitle!.isNotEmpty)
                        Text(
                          widget.currentProgramTitle!,
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
                if (_isLive)
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
            // Center: play/pause
            Icon(
              playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.white,
              size: 64,
            ),
            const Spacer(),
            // Bottom: progress (VOD) or hint (live)
            if (!_isLive && dur.inSeconds > 0) ...[
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
              const SizedBox(height: 6),
              const Text(
                'OK: oynat/duraklat   ‹ ›: 10sn sar',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ] else if (_isLive)
              const Text(
                'OK: oynat/duraklat   ▲▼: kanal değiştir',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
