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
import 'package:lifeostv/data/repositories/profile_repository.dart'
    show activeProfileIdProvider;
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
/// D-pad controls, live channel/EPG panels, audio/subtitle and quality
/// selection share this route. Cast integration remains separate work.
class TvVideoPlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final Map<String, String> httpHeaders;
  final int streamId;
  final int? accountId;
  final String title;
  final VideoType type;
  final String? logo;
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
    this.httpHeaders = const {},
    required this.streamId,
    this.accountId,
    required this.title,
    this.type = VideoType.live,
    this.logo,
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
  VideoPlayerController? _controller;
  TvSubtitleController? _subtitles;
  bool _subtitleVisible = false;
  final _focusNode = FocusNode();

  bool _showControls = true;
  bool _modalOpen = false;
  _TvPanel? _panel;
  late final AppDatabase _sessionDb;
  StreamSubscription<List<Program>>? _epgSubscription;
  List<Program> _programs = [];
  Timer? _epgClock;
  int get _activeChannelId {
    final channels = widget.channels;
    return channels != null &&
            _channelIndex >= 0 &&
            _channelIndex < channels.length
        ? channels[_channelIndex].streamId
        : widget.streamId;
  }

  String? get _programTitle {
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

  // Current stream for the active playback (changes on live channel switch).
  late String _url;
  Map<String, String> _headers = const {};
  late String _title;
  String? _logo;
  late int _channelIndex;

  bool get _isLive => widget.type == VideoType.live;

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
    WidgetsBinding.instance.addObserver(this);
    playbackActiveNotifier.value = true;
    _url = widget.streamUrl;
    _headers = widget.httpHeaders;
    _title = widget.title;
    _logo = widget.logo;
    _channelIndex = widget.currentChannelIndex ?? 0;
    if (_isLive) {
      _watchEpg();
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
    _epgClock?.cancel();
    _epgSubscription?.cancel();
    _saveTimer?.cancel();
    _controller?.removeListener(_onValue);
    final retiring = _controller;
    if (retiring != null) unawaited(_retireController(retiring));
    _focusNode.dispose();
    _episodePlayFocus.dispose();
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

  Future<void> _retireController(VideoPlayerController c) async {
    await (_controllerWork[c] ?? Future<void>.value());
    await c.dispose().catchError((Object _) {});
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
    // Tear down any previous controller (channel switch / retry).
    final old = _controller;
    _controller = null;
    _subtitles = null;
    _subtitleVisible = false;
    old?.removeListener(_onValue);
    if (old != null) await _retireController(old);
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
      await c.initialize().timeout(const Duration(seconds: 25));
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
      if (resume != null && resume > Duration.zero && !_isLive) {
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
        await _retireController(c);
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
    if (!_savedInitialProgress &&
        ((_isLive && v.isPlaying) ||
            (!_isLive &&
                v.position.inSeconds >= 3 &&
                v.duration.inSeconds >= 10))) {
      _savedInitialProgress = true;
      _saveProgress();
    }
    // Keep the bottom-bar position/duration live while controls are shown.
    if (_showControls) setState(() {});
  }

  // ── Controls visibility ───────────────────────────────────────────────

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_error != null || _modalOpen || _panel != null) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _focusNode.requestFocus();
        setState(() => _showControls = false);
      }
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
      unawaited(_command(c, c.pause));
    } else {
      unawaited(_command(c, c.play));
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
    unawaited(_saveProgress());
    _channelIndex = idx;
    final ch = chans[idx];
    setState(() {
      _url = ch.url;
      _headers = ch.httpHeaders;
      _title = ch.name;
      _logo = ch.logo;
    });
    _watchEpg();
    _open(ch.url);
    _showControlsBriefly();
  }

  Future<void> _saveProgress() async {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized || (!_isLive && v.duration.inSeconds < 10)) return;
    final posMs = v.position.inMilliseconds;
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
          v.duration.inMilliseconds,
          parentSeriesId: widget.saveSeriesSummary
              ? widget.parentStreamId
              : null,
        );
      } else {
        await repo.saveProgress(
          sid,
          widget.type.name,
          _isLive ? 1 : posMs,
          _isLive ? 100 : v.duration.inMilliseconds,
        );
      }
    } catch (_) {}
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
                    p.stop.isBiggerThanValue(DateTime.now()),
              )
              ..orderBy([(p) => OrderingTerm(expression: p.start)]))
            .watch()
            .listen((programs) {
              if (!mounted || id != _activeChannelId) return;
              _programs = programs;
              if (_showControls || _panel == _TvPanel.epg) setState(() {});
            }, onError: (Object _) {});
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

  void _closePanel() {
    if (!mounted || _panel == null) return;
    setState(() => _panel = null);
    _showControlsBriefly();
    _episodePlayFocus.requestFocus();
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
    final subtitles = _subtitles;
    if (_modalOpen || subtitles == null) return;
    _modalOpen = true;
    _hideTimer?.cancel();
    final generation = _openGeneration;
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
        _episodePlayFocus.requestFocus();
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
        startAt: _isLive ? null : position,
        autoplay: wasPlaying,
      );
    } finally {
      _modalOpen = false;
      if (mounted && expectedGeneration == _openGeneration) {
        _showControlsBriefly();
        _episodePlayFocus.requestFocus();
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
        _episodePlayFocus.requestFocus();
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
    // Let focused episode buttons handle activation and directional traversal.
    if (!_focusNode.hasPrimaryFocus && _showControls && _error == null) {
      _resetHideTimer();
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (_isLive) {
        _openPanel(_TvPanel.channels);
      } else {
        _seekBy(-10);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_isLive) {
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
        _episodePlayFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_isLive) {
        _channelStep(1);
      } else {
        _showControlsBriefly();
        _episodePlayFocus.requestFocus();
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
                if (v != null && v.isInitialized)
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
                if (_buffering && _error == null)
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
                      if (index != _channelIndex)
                        _channelStep(index - _channelIndex);
                      _closePanel();
                    },
                    onClose: _closePanel,
                  ),
                if (_panel == _TvPanel.epg)
                  EpgOverlay(
                    programs: _programs
                        .where((p) => p.stop.isAfter(DateTime.now()))
                        .toList(),
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
                        _title,
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
            // Same episode callbacks and stable IDs as the desktop player.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onPrevEpisode != null)
                  IconButton(
                    key: const ValueKey('previous-episode'),
                    tooltip: widget.previousEpisodeTitle,
                    onPressed: () => _switchEpisode(widget.onPrevEpisode),
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                  ),
                IconButton(
                  focusNode: _episodePlayFocus,
                  key: const ValueKey('episode-play-pause'),
                  onPressed: _togglePlay,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
                if (widget.onNextEpisode != null)
                  IconButton(
                    key: const ValueKey('next-episode'),
                    tooltip:
                        widget.nextEpisodeTitle ??
                        AppLocalizations.of(context)!.nextEpisode,
                    onPressed: () => _switchEpisode(widget.onNextEpisode),
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLive)
                  IconButton(
                    key: const ValueKey('tv-channel-list'),
                    tooltip: AppLocalizations.of(context)!.channelList,
                    onPressed: () => _openPanel(_TvPanel.channels),
                    icon: const Icon(Icons.list, color: Colors.white),
                  ),
                IconButton(
                  key: const ValueKey('tv-audio-tracks'),
                  tooltip: AppLocalizations.of(context)!.audioTrack,
                  onPressed: v?.isInitialized == true
                      ? _chooseAudioTrack
                      : null,
                  icon: const Icon(Icons.audiotrack, color: Colors.white),
                ),
                if (_subtitles != null)
                  IconButton(
                    key: const ValueKey('tv-subtitles'),
                    tooltip: AppLocalizations.of(context)!.subtitle,
                    onPressed: _chooseSubtitles,
                    icon: const Icon(Icons.subtitles, color: Colors.white),
                  ),
                IconButton(
                  key: const ValueKey('tv-quality'),
                  tooltip: AppLocalizations.of(context)!.streamQuality,
                  onPressed: v?.isInitialized == true ? _chooseQuality : null,
                  icon: const Icon(Icons.high_quality, color: Colors.white),
                ),
                if (_isLive)
                  IconButton(
                    key: const ValueKey('tv-program-guide'),
                    tooltip: AppLocalizations.of(context)!.programGuide,
                    onPressed: () => _openPanel(_TvPanel.epg),
                    icon: const Icon(Icons.view_list, color: Colors.white),
                  ),
              ],
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
                'OK: oynat/duraklat   ▲▼: kanal   ◀: liste   ▶: rehber   Menü: kontroller',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
