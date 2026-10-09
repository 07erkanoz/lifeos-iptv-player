import 'package:lifeostv/core/managed_player.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/data/services/youtube_trailer_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/youtube_trailer.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart' as native;

({double width, double height}) computeExpandedTrailerSize(
  Size viewport, {
  double scale = 0.9,
}) {
  final maxW = viewport.width * scale;
  final maxH = viewport.height * scale;
  double w = maxW;
  double h = w * 9 / 16;
  if (h > maxH) {
    h = maxH;
    w = h * 16 / 9;
  }
  return (width: w, height: h);
}

Future<void> showExpandedTrailer(
  BuildContext context, {
  required String? directTrailerRef,
  required String searchTitle,
  required String? searchYear,
  required String channelType,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ExpandedTrailerDialog(
      directTrailerRef: directTrailerRef,
      searchTitle: searchTitle,
      searchYear: searchYear,
      channelType: channelType,
    ),
  );
}

class _ExpandedTrailerDialog extends StatefulWidget {
  const _ExpandedTrailerDialog({
    required this.directTrailerRef,
    required this.searchTitle,
    required this.searchYear,
    required this.channelType,
  });

  final String? directTrailerRef;
  final String searchTitle;
  final String? searchYear;
  final String channelType;

  @override
  State<_ExpandedTrailerDialog> createState() => _ExpandedTrailerDialogState();
}

class _ExpandedTrailerDialogState extends State<_ExpandedTrailerDialog> {
  final FocusNode _closeFocus = FocusNode(debugLabel: 'TrailerClose');
  final FocusNode _retryFocus = FocusNode(debugLabel: 'TrailerRetry');
  native.VideoPlayerController? _nativePlayer;
  Player? _mediaPlayer;
  VideoController? _mediaController;
  StreamSubscription<String>? _errorSubscription;
  Timer? _startupTimer;
  bool _loading = true;
  bool _failed = false;
  bool _playing = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
    _load();
  }

  @override
  void dispose() {
    ++_request;
    _disposePlayers();
    _closeFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  void _disposePlayers() {
    _startupTimer?.cancel();
    _startupTimer = null;
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _nativePlayer?.dispose();
    _nativePlayer = null;
    _mediaPlayer?.dispose();
    _mediaPlayer = null;
    _mediaController = null;
  }

  Future<void> _load() async {
    final request = ++_request;
    _disposePlayers();
    setState(() {
      _loading = true;
      _failed = false;
      _playing = false;
    });
    try {
      if (widget.channelType == 'live') throw StateError('No live trailer');
      String? url;
      final ref = widget.directTrailerRef;
      if (ref != null && ref.trim().isNotEmpty) {
        url = await YouTubeTrailerService.instance
            .extractStreamUrl(ref, requireAudio: true)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
      }
      if (url == null && widget.searchTitle.trim().isNotEmpty) {
        url = await YouTubeTrailerService.instance
            .extractStreamUrlForQuery(
              widget.searchTitle,
              year: widget.searchYear,
              requireAudio: true,
            )
            .timeout(const Duration(seconds: 12), onTimeout: () => null);
      }
      if (!mounted || request != _request) return;
      if (url == null) throw StateError('No playable audio-video trailer');

      if (PlatformHelper.isTV) {
        // Android TV uses the same platform decoder as VOD.
        final player = native.VideoPlayerController.networkUrl(Uri.parse(url));
        _nativePlayer = player;
        player.addListener(() {
          if (mounted && request == _request && player.value.hasError) {
            _showFailure();
          }
        });
        await player.initialize().timeout(const Duration(seconds: 15));
        if (!mounted || request != _request) return;
        await player.setLooping(true);
        await player.play();
        _startupTimer = Timer(const Duration(seconds: 12), () {
          if (mounted &&
              request == _request &&
              _playing &&
              player.value.position == Duration.zero) {
            _showFailure();
          }
        });
      } else {
        final player = ManagedPlayer();
        _mediaPlayer = player;
        _mediaController = VideoController(player);
        _errorSubscription = player.stream.error.listen((_) {
          if (mounted && request == _request) _showFailure();
        });
        await player.setPlaylistMode(PlaylistMode.loop);
        await player
            .open(Media(url), play: true)
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted || request != _request || _failed) return;
      setState(() {
        _loading = false;
        _playing = true;
      });
    } catch (_) {
      if (mounted && request == _request) _showFailure();
    }
  }

  void _showFailure() {
    if (_failed) return;
    _disposePlayers();
    setState(() {
      _loading = false;
      _failed = true;
      _playing = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _retryFocus.context?.mounted == true) {
        _retryFocus.requestFocus();
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_loading || _failed) return;
    if (_nativePlayer != null) {
      if (_playing) {
        await _nativePlayer!.pause();
      } else {
        await _nativePlayer!.play();
      }
    } else if (_mediaPlayer != null) {
      await _mediaPlayer!.playOrPause();
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  Future<void> _openOnYouTube() async {
    final direct = widget.directTrailerRef?.trim();
    final url = direct != null && Uri.tryParse(direct)?.hasScheme == true
        ? direct
        : youtubeSearchTrailerUrl(widget.searchTitle, year: widget.searchYear);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final size = computeExpandedTrailerSize(MediaQuery.sizeOf(context));
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_nativePlayer?.value.isInitialized == true)
                  native.VideoPlayer(_nativePlayer!)
                else if (_mediaController != null && !_failed)
                  Video(
                    controller: _mediaController!,
                    controls: NoVideoControls,
                    fill: Colors.black,
                    fit: BoxFit.contain,
                  ),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.streamLoadFailed,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          children: [
                            ElevatedButton.icon(
                              focusNode: _retryFocus,
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: Text(l10n.retry),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openOnYouTube,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('YouTube'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (!_loading && !_failed)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IconButton.filledTonal(
                      onPressed: _togglePlayback,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    ),
                  ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filledTonal(
                    focusNode: _closeFocus,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
