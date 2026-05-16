import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lifeostv/data/services/youtube_trailer_service.dart';

/// Renders a backdrop image and, after a short delay, fades in a muted
/// looping YouTube trailer on top of it. Used by the movie / series
/// detail views to give every detail screen the Netflix billboard
/// moment.
///
/// If the backdrop image is missing OR trailer extraction fails the
/// widget gracefully degrades — caller never sees an error, just the
/// best available representation.
///
/// The widget owns its own Player + VideoController and disposes
/// them in dispose(); safe to drop into any screen without lifecycle
/// gymnastics from the parent.
class BackdropTrailer extends StatefulWidget {
  /// Image used as the still backdrop and as the visible state until
  /// the trailer (if any) extracts and starts playing.
  final String? backdropUrl;

  /// Direct YouTube reference — bare 11-char id, full watch URL, or
  /// youtu.be short URL. Preferred path when the IPTV provider ships
  /// a real trailer id; otherwise pass null and rely on the search
  /// fallback below.
  final String? directTrailerRef;

  /// Used to build a "<title> [year] trailer" YouTube search query
  /// when [directTrailerRef] is null/empty. Most IPTV providers omit
  /// the trailer field, so this is the path that actually fires.
  final String searchTitle;
  final String? searchYear;

  /// How long to show the static backdrop before kicking off
  /// extraction. Gives the user time to register the still image and
  /// avoids burning a YouTube request when they immediately close
  /// the detail view.
  final Duration delay;

  /// Channel type — live channels skip extraction entirely (no
  /// concept of a trailer for live TV).
  final String channelType;

  /// When false, only the trailer video is rendered (no still backdrop
  /// fallback). Used by compact "picture-in-picture" placements where
  /// the caller owns its own visual fallback or wants the box to be
  /// blank until the trailer extracts.
  final bool showBackdrop;

  /// Whether to start muted. PiP previews stay muted to avoid surprise
  /// audio; the expanded fullscreen dialog opens with sound on.
  final bool muted;

  const BackdropTrailer({
    super.key,
    required this.backdropUrl,
    required this.directTrailerRef,
    required this.searchTitle,
    required this.searchYear,
    required this.channelType,
    this.delay = const Duration(milliseconds: 1500),
    this.showBackdrop = true,
    this.muted = true,
  });

  @override
  State<BackdropTrailer> createState() => _BackdropTrailerState();
}

class _BackdropTrailerState extends State<BackdropTrailer> {
  Player? _player;
  VideoController? _controller;
  Timer? _scheduleTimer;
  int _requestId = 0;
  bool _trailerVisible = false;

  @override
  void initState() {
    super.initState();
    _scheduleTrailer();
  }

  @override
  void didUpdateWidget(covariant BackdropTrailer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the channel changed (e.g. user navigated to a different
    // detail without unmounting), restart extraction from scratch.
    if (widget.directTrailerRef != oldWidget.directTrailerRef ||
        widget.searchTitle != oldWidget.searchTitle ||
        widget.searchYear != oldWidget.searchYear) {
      _disposePlayer();
      setState(() => _trailerVisible = false);
      _scheduleTrailer();
    }
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    _disposePlayer();
    super.dispose();
  }

  void _scheduleTrailer() {
    _scheduleTimer?.cancel();
    if (widget.channelType == 'live') return;

    final reqId = ++_requestId;
    _scheduleTimer = Timer(widget.delay, () {
      if (mounted) _startTrailer(reqId);
    });
  }

  Future<void> _startTrailer(int reqId) async {
    String? streamUrl;
    try {
      final ref = widget.directTrailerRef;
      if (ref != null && ref.trim().isNotEmpty) {
        streamUrl =
            await YouTubeTrailerService.instance.extractStreamUrl(ref);
      }
      // Fallback: providers often ship garbage (empty, "N/A", broken
      // ids) in youtube_trailer. If direct extraction yielded nothing,
      // try the title-based search so VODs with no usable trailer
      // field still light up the billboard.
      if (streamUrl == null && widget.searchTitle.trim().isNotEmpty) {
        streamUrl = await YouTubeTrailerService.instance
            .extractStreamUrlForQuery(widget.searchTitle,
                year: widget.searchYear);
      }
    } catch (_) {
      return;
    }
    if (!mounted || reqId != _requestId || streamUrl == null) return;

    final player = Player();
    final controller = VideoController(player);
    try {
      await player.setVolume(widget.muted ? 0 : 100);
      await player.setPlaylistMode(PlaylistMode.loop);
      await player.open(Media(streamUrl), play: true);
    } catch (_) {
      player.dispose();
      return;
    }
    if (!mounted || reqId != _requestId) {
      player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _controller = controller;
      _trailerVisible = true;
    });
  }

  void _disposePlayer() {
    final p = _player;
    _player = null;
    _controller = null;
    p?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.backdropUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Static backdrop — always present as the base layer so even
        // when the trailer hasn't loaded (or never will) the screen
        // never goes blank. Skipped when showBackdrop=false (compact
        // PiP mode where the caller owns the fallback visual).
        if (widget.showBackdrop) ...[
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
            )
          else
            const ColoredBox(color: Colors.black),
        ],

        // Trailer fades in once extraction succeeds.
        if (_controller != null)
          AnimatedOpacity(
            opacity: _trailerVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 600),
            child: Video(
              controller: _controller!,
              fill: Colors.black,
              controls: NoVideoControls,
              fit: BoxFit.cover,
            ),
          ),
      ],
    );
  }
}
