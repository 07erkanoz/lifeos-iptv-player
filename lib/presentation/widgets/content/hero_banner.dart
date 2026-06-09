import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/youtube_trailer_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/ui/empty_state.dart';

/// Data class for hero VOD info (fetched from API)
class HeroVodInfo {
  final String? plot;
  final String? genre;
  final String? director;
  final String? cast;
  final double? rating;
  final String? duration;
  final String? youtubeTrailer;
  final String? backdropUrl;

  const HeroVodInfo({
    this.plot,
    this.genre,
    this.director,
    this.cast,
    this.rating,
    this.duration,
    this.youtubeTrailer,
    this.backdropUrl,
  });
}

class HeroBanner extends ConsumerStatefulWidget {
  final List<Channel> channels;
  final Function(Channel)? onPlay;
  final Function(Channel)? onDetails;
  final Function(Channel)? onTrailer;

  /// Called when hero item changes - parent should fetch VOD info
  final Function(Channel)? onItemChanged;

  /// Current VOD info for the active hero item
  final HeroVodInfo? vodInfo;

  /// External FocusNode wired into the Play button so the parent
  /// (DashboardScreen) can register it as the branch's primary focus
  /// target with [TvFocusRegistry]. Sidebar → right then lands on
  /// Play instead of an indeterminate first focusable.
  final FocusNode? playFocusNode;

  /// Fires on D-pad left from the Play button. Wired by
  /// DashboardScreen to `TvFocusRegistry.requestMainSidebar()` so the
  /// natural left gesture from the leftmost action button surfaces
  /// the nav.
  final VoidCallback? onLeftEdge;

  /// Optional map from streamId → AI-generated hook tagline. When
  /// the currently-displayed hero item's streamId has an entry, the
  /// hero overlay renders the tagline right below the title with a
  /// ✨ marker. Null/empty when the user has no Gemini key or the
  /// billboard provider hasn't finished yet — in that case the hero
  /// looks identical to its pre-AI baseline.
  final Map<int, String>? aiTaglines;

  const HeroBanner({
    super.key,
    required this.channels,
    this.onPlay,
    this.onDetails,
    this.onTrailer,
    this.onItemChanged,
    this.vodInfo,
    this.playFocusNode,
    this.onLeftEdge,
    this.aiTaglines,
  });

  @override
  ConsumerState<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends ConsumerState<HeroBanner> {
  int _currentIndex = 0;
  Timer? _autoSlideTimer;
  int _lastChannelCount = 0;

  // ── Trailer preview state ──
  // We extract the YouTube stream URL into a media_kit Player so the
  // hero plays a muted, looping trailer behind the title overlay
  // (Netflix billboard pattern). Reset on every hero item change.
  Player? _trailerPlayer;
  VideoController? _trailerController;
  Timer? _trailerScheduleTimer;
  int _trailerRequestId = 0; // bumped on every change to invalidate stale requests
  bool _trailerVisible = false;
  /// Cached resolved stream URL for the currently-playing preview.
  /// When the user taps the trailer to expand into the Netflix-style
  /// fullscreen viewer, we hand this URL to a fresh sound-enabled
  /// Player rather than transferring the muted preview's instance —
  /// avoids media_kit state-contamination when two `Video` widgets
  /// race over the same controller during the modal animation.
  String? _trailerStreamUrl;
  /// True while the expanded fullscreen trailer route is on-screen.
  /// Auto-slide is suppressed in this window so the title doesn't
  /// rotate out from underneath the user mid-trailer.
  bool _trailerExpanded = false;

  bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 600;

  /// Detects 10-foot-UI (Android TV, large desktop with TV-like
  /// aspect). Used to push hero a notch taller because TV viewports
  /// are landscape-tall — a 280 px hero on 1080p TV is only 26 %
  /// of the screen and feels like a letterbox bar.
  ///
  /// Threshold: width ≥ 1280 AND shortestSide ≥ 600. shortestSide
  /// catches the actual 16:9 TV case while excluding a 1280-wide
  /// laptop in portrait mode.
  bool _isTv(BuildContext context) {
    final s = MediaQuery.of(context).size;
    return s.width >= 1280 && s.shortestSide >= 600;
  }

  /// Viewport-relative hero height. Replaces the old fixed 200 / 280
  /// px values, which looked correct on a 720p window but turned
  /// "letterbox-shallow" on 1080p / 4K desktops and on Android TV.
  ///
  /// Anchors:
  ///   * mobile   → 220 px fixed (small screens, rail-first layout)
  ///   * desktop  → ~55 % of viewport, clamped 360–560 px
  ///   * TV       → ~62 % of viewport, clamped 440–760 px
  ///     (62 % keeps a sliver of the next rail visible at the bottom,
  ///      which is the Netflix Android TV "peek" convention so the
  ///      user knows to scroll.)
  double _heroHeight(BuildContext context) {
    final mobile = _isMobile(context);
    if (mobile) return 220.0;
    final h = MediaQuery.of(context).size.height;
    if (_isTv(context)) {
      return (h * 0.62).clamp(440.0, 760.0);
    }
    return (h * 0.55).clamp(360.0, 560.0);
  }

  @override
  void initState() {
    super.initState();
    _lastChannelCount = widget.channels.length;
    _startAutoSlide();
    // Notify parent of initial item
    if (widget.channels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onItemChanged?.call(widget.channels[0]);
        _scheduleTrailer(widget.channels[0]);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Channels list changed (e.g. async data loaded) → restart auto-slide
    if (widget.channels.length != _lastChannelCount) {
      _lastChannelCount = widget.channels.length;
      // Clamp current index to valid range
      if (_currentIndex >= widget.channels.length) {
        _currentIndex = 0;
      }
      _startAutoSlide();
      // Notify parent of current item after channels changed.
      // Deferred to post-frame because didUpdateWidget runs inside the
      // parent's build; calling setState on the parent synchronously
      // here would throw "setState during build".
      if (widget.channels.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onItemChanged?.call(widget.channels[_currentIndex]);
        });
        _scheduleTrailer(widget.channels[_currentIndex]);
      }
    }

    // VOD info arrived asynchronously after the parent fetched it from
    // the Xtream API — that's where most YouTube trailer ids actually
    // live (DB cache is usually empty until the user opens detail).
    // Trigger trailer scheduling now that we finally have a non-null
    // trailer reference.
    final newTrailer = widget.vodInfo?.youtubeTrailer;
    final oldTrailer = oldWidget.vodInfo?.youtubeTrailer;
    if (newTrailer != oldTrailer &&
        newTrailer != null &&
        newTrailer.trim().isNotEmpty &&
        widget.channels.isNotEmpty) {
      _scheduleTrailer(widget.channels[_currentIndex]);
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _trailerScheduleTimer?.cancel();
    _disposeTrailerPlayer();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (widget.channels.length > 1) {
      _autoSlideTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (!mounted) return;
        // Don't rotate while the user is watching the expanded trailer
        // — would yank the title out from under them. The timer keeps
        // ticking but each fire is a no-op until the modal closes.
        if (_trailerExpanded) return;
        final newIndex = (_currentIndex + 1) % widget.channels.length;
        setState(() => _currentIndex = newIndex);
        widget.onItemChanged?.call(widget.channels[newIndex]);
        _scheduleTrailer(widget.channels[newIndex]);
      });
    }
  }

  void _goToIndex(int index) {
    if (index == _currentIndex || index < 0 || index >= widget.channels.length) return;
    setState(() => _currentIndex = index);
    widget.onItemChanged?.call(widget.channels[index]);
    _scheduleTrailer(widget.channels[index]);
    _startAutoSlide(); // Reset timer
  }

  // ───────────────────────── Trailer preview ─────────────────────────

  /// Tear down the previous preview and queue extraction for [channel]
  /// after a short delay (so rapid swipes don't burn YouTube requests
  /// and the user gets time to see the still backdrop first).
  ///
  /// Pulls the trailer reference from widget.vodInfo first (freshest —
  /// the parent fetches it asynchronously from the Xtream API on every
  /// hero change), then falls back to channel.youtubeTrailer (DB
  /// cache from a previous detail-page open).
  void _scheduleTrailer(Channel channel) {
    _trailerScheduleTimer?.cancel();
    // ⚠️ Don't dispose the Player here.
    //
    // Earlier this method nuked the existing _trailerPlayer on every
    // hero rotation, then _startTrailer instantiated a fresh one. On
    // Wayland (KDE + AMD) media_kit re-acquires the EGL surface on
    // each Player constructor → compositor flashes white briefly →
    // user perceives a dashboard-wide flicker every 12 seconds.
    //
    // Fix: keep the Player alive across rotations. We just `stop()`
    // the current playback, fade out the overlay, and the next
    // _startTrailer call swaps the source via player.open() on the
    // same instance. Same EGL surface, no compositor churn.
    _trailerPlayer?.stop();
    setState(() {
      _trailerVisible = false;
      _trailerStreamUrl = null;
    });

    // Live channels don't have trailers; mobile is data sensitive
    // so we only autoplay when the user has explicitly opted in via
    // Settings → "Anasayfa fragmanını oynat". TV is skipped because
    // the hero auto-rotates every 12s and on TV that meant a new
    // YouTube extract + libmpv Player init every cycle — visible
    // jank during D-pad navigation and constant GPU contention with
    // the main IPTV decoder.
    if (channel.type == 'live') return;
    if (_isMobile(context) &&
        !ref.read(settingsProvider).heroTrailerOnMobile) {
      return;
    }
    if (PlatformHelper.isTV) return;

    final fromApi = widget.vodInfo?.youtubeTrailer;
    final fromDb = channel.youtubeTrailer;
    final directRef =
        (fromApi != null && fromApi.trim().isNotEmpty) ? fromApi : fromDb;

    // If we don't have a direct YouTube id, the start path will fall
    // back to searching YouTube for "<name> [year] trailer". We still
    // queue an attempt — most IPTV providers leave youtube_trailer
    // empty and search is what actually fires for them.
    final reqId = ++_trailerRequestId;
    _trailerScheduleTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _startTrailer(channel, directRef, reqId);
    });
  }

  Future<void> _startTrailer(Channel channel, String? directRef, int reqId) async {
    String? streamUrl;
    try {
      if (directRef != null && directRef.trim().isNotEmpty) {
        streamUrl =
            await YouTubeTrailerService.instance.extractStreamUrl(directRef);
      } else {
        streamUrl = await YouTubeTrailerService.instance
            .extractStreamUrlForQuery(channel.name, year: channel.year);
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (reqId != _trailerRequestId) return;
    if (streamUrl == null) return;

    // Reuse the existing Player instance when we have one — only
    // construct on the very first trailer (or after dispose() in
    // widget teardown). See [_scheduleTrailer] comment for the
    // Wayland flicker rationale.
    final bool freshPlayer = _trailerPlayer == null;
    final Player player;
    final VideoController controller;
    if (freshPlayer) {
      player = Player();
      controller = VideoController(player);
    } else {
      player = _trailerPlayer!;
      controller = _trailerController!;
    }

    try {
      if (freshPlayer) {
        // One-time setup. setVolume + loop mode persist across
        // subsequent open() calls, so we only configure them once.
        await player.setVolume(0);
        await player.setPlaylistMode(PlaylistMode.loop);
      }
      // open() swaps the source on the existing surface without
      // touching the EGL context — no compositor flicker.
      await player.open(Media(streamUrl), play: true);
    } catch (_) {
      // Only dispose if this was a fresh Player that never made it
      // into state — a reused one stays alive for the next attempt.
      if (freshPlayer) player.dispose();
      return;
    }

    if (!mounted || reqId != _trailerRequestId) {
      if (freshPlayer) player.dispose();
      return;
    }

    setState(() {
      _trailerPlayer = player;
      _trailerController = controller;
      _trailerVisible = true;
      _trailerStreamUrl = streamUrl;
    });
  }

  /// Suspend / resume the muted hero preview while the expanded
  /// fullscreen trailer modal is showing. We pause the preview's
  /// libmpv decoder while the modal is up — running two libmpv
  /// instances on the same stream simultaneously is technically OK
  /// but burns CPU on lower-end Android TV / desktop boxes for no
  /// visible gain (the preview is fully covered by the modal).
  void _pausePreviewForExpand() {
    _autoSlideTimer?.cancel();
    _trailerPlayer?.pause();
  }

  void _resumePreviewAfterExpand() {
    _trailerPlayer?.play();
    _startAutoSlide();
  }

  /// Open the Netflix-style fullscreen trailer viewer. Triggered by
  /// tapping the muted preview region of the hero (everything that
  /// isn't the title / button / chip block in the lower-left). Falls
  /// back to the existing external-browser launch via `widget
  /// .onTrailer` when no in-app stream is ready yet (e.g. the user
  /// tapped before extraction finished, or extraction failed and we
  /// only have a YouTube URL).
  Future<void> _openTrailerExpanded(Channel channel) async {
    final url = _trailerStreamUrl;
    if (url == null || url.isEmpty) {
      // No in-app stream → defer to the existing external-trailer
      // path so the user still gets *some* trailer experience.
      widget.onTrailer?.call(channel);
      return;
    }
    setState(() => _trailerExpanded = true);
    _pausePreviewForExpand();
    try {
      await Navigator.of(context, rootNavigator: true).push(
        _TrailerFullscreenRoute(streamUrl: url, title: channel.name),
      );
    } finally {
      if (mounted) {
        setState(() => _trailerExpanded = false);
        _resumePreviewAfterExpand();
      }
    }
  }

  void _disposeTrailerPlayer() {
    final p = _trailerPlayer;
    _trailerPlayer = null;
    _trailerController = null;
    p?.dispose();
  }

  void _goNext() {
    if (widget.channels.length <= 1) return;
    _goToIndex((_currentIndex + 1) % widget.channels.length);
  }

  void _goPrev() {
    if (widget.channels.length <= 1) return;
    _goToIndex((_currentIndex - 1 + widget.channels.length) % widget.channels.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mobile = _isMobile(context);

    // React to the mobile-trailer toggle while the hero is on
    // screen. Without this, the user has to leave the dashboard and
    // come back before flipping the setting takes effect.
    ref.listen<bool>(
      settingsProvider.select((s) => s.heroTrailerOnMobile),
      (prev, next) {
        if (!mounted) return;
        if (!_isMobile(context)) return;
        if (next) {
          if (widget.channels.isNotEmpty) {
            _scheduleTrailer(widget.channels[_currentIndex]);
          }
        } else {
          _trailerScheduleTimer?.cancel();
          _trailerPlayer?.stop();
          setState(() {
            _trailerVisible = false;
            _trailerStreamUrl = null;
          });
        }
      },
    );

    // Viewport-relative height — see [_heroHeight]. Old code used
    // fixed 200/280 px which looked correct on 720 p windows but
    // squished on 1080 p+ desktops and on Android TV. Mobile still
    // gets a small fixed value because viewport-relative on a
    // 6-inch phone would either crowd the rail-first layout or
    // exaggerate the hero.
    final clampedHeight = _heroHeight(context);

    if (widget.channels.isEmpty) {
      return SizedBox(
        height: clampedHeight,
        child: EmptyState.library(
          title: l10n.noChannels,
        ),
      );
    }

    final channel = widget.channels[_currentIndex];
    // Use backdrop from API info first, then DB cached, then poster
    final backdropUrl = widget.vodInfo?.backdropUrl ?? channel.backdropPath;
    final hasBackdrop = backdropUrl != null && backdropUrl.isNotEmpty;
    // Rating from API info first, then DB
    final rating = widget.vodInfo?.rating ?? channel.rating;

    return GestureDetector(
      onHorizontalDragEnd: widget.channels.length > 1
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) {
                _goNext(); // Swipe left → next
              } else if (velocity > 200) {
                _goPrev(); // Swipe right → previous
              }
            }
          : null,
      child: SizedBox(
        height: clampedHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background Image ──
            // ── Background Image — same approach as movies/series hero ──
            AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: _buildHeroImage(channel, backdropUrl, hasBackdrop),
          ),

          // ── Trailer overlay (fades in once YouTube extraction completes) ──
          if (_trailerController != null)
            AnimatedOpacity(
              opacity: _trailerVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 600),
              child: Video(
                controller: _trailerController!,
                fill: Colors.black,
                controls: NoVideoControls,
                fit: BoxFit.cover,
              ),
            ),

          // ── Left gradient (same as movies hero) ──
          // Wrapped in IgnorePointer so the gradient — which used to
          // sit above the tap-to-expand layer in the Stack and silently
          // absorb every click on the backdrop — passes hits through
          // to the layer below.
          IgnorePointer(
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft, end: Alignment.centerRight,
                colors: [
                  AppColors.backgroundDark.withValues(alpha: 0.85),
                  AppColors.backgroundDark.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.7],
              ),
            )),
          ),

          // ── Bottom gradient (same as movies hero) ──
          IgnorePointer(
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [
                  AppColors.backgroundDark,
                  AppColors.backgroundDark.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.2, 0.5],
              ),
            )),
          ),

          // ── Tap-to-expand layer ──
          // Placed AFTER the gradients so it sits on top of them in
          // hit-test order. The content overlay (badges / title /
          // buttons / dots) is added next, so it sits on top of *this*
          // and absorbs taps in its own Positioned rect — buttons keep
          // working normally; only the backdrop region around them
          // triggers the trailer expand.
          if (_trailerVisible && _trailerStreamUrl != null)
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint('[hero] trailer tap → openTrailerExpanded');
                    _openTrailerExpanded(channel);
                  },
                  child: Stack(
                    children: [
                      // Top-right hint badge — "Fragmanı izle"
                      // affordance so users know the muted preview is
                      // interactive. IgnorePointer so it doesn't eat
                      // the tap meant for the layer behind it.
                      Positioned(
                        top: 16,
                        right: 16,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _trailerVisible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 400),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.18)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.volume_off_rounded,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.watchTrailer,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Content overlay — same positioning as movies hero ──
          Positioned(
            bottom: mobile ? 12 : 20,
            left: mobile ? 16 : 24,
            right: mobile ? 16 : 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badges row
                _buildBadges(channel, l10n, rating),
                const SizedBox(height: 10),

                // Title (same style as movies hero: fontSize 24, w800)
                Text(
                  channel.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: mobile ? 18 : 24,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // ── AI tagline ──────────────────────────────────
                // Rendered only when the parent passed a non-null
                // [aiTaglines] map and the current channel has an
                // entry. Without a Gemini key the parent passes
                // null here, so the hero falls back to the
                // pre-AI title → chips → plot layout pixel-for-pixel.
                if (widget.aiTaglines != null &&
                    (widget.aiTaglines![channel.streamId]?.isNotEmpty ??
                        false)) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.aiTaglines![channel.streamId]!,
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.95),
                            fontSize: mobile ? 12 : 13,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // Genre chips (same style as movies hero)
                if (!mobile && _genreText(channel) != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: _genreText(channel)!.split(',').take(4).map((g) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Text(g.trim(), style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 10)),
                    )).toList(),
                  ),
                ],

                // Plot (same style as movies hero: 150 char, 2 lines)
                if (!mobile && _plotText(channel) != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _truncatePlot(_plotText(channel)!, 150),
                    style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 12, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 14),

                // Action buttons
                Row(
                  children: [
                    _HeroButton(
                      icon: Icons.play_arrow,
                      label: l10n.play,
                      isPrimary: true,
                      onTap: () => widget.onPlay?.call(channel),
                      focusNode: widget.playFocusNode,
                      onLeftEdge: widget.onLeftEdge,
                    ),
                    const SizedBox(width: 10),
                    _HeroButton(
                      icon: Icons.info_outline,
                      label: l10n.details,
                      isPrimary: false,
                      onTap: () => widget.onDetails?.call(channel),
                    ),
                    // Trailer button (if available). Route through
                    // _openTrailerExpanded so:
                    //   * TV remote D-pad lands here (the button is
                    //     already Focus-wrapped via _HeroButton) and
                    //     opens the in-app fullscreen viewer, not
                    //     an external browser that the TV may not
                    //     have configured.
                    //   * When the in-app stream URL isn't ready,
                    //     _openTrailerExpanded falls back to the
                    //     onTrailer callback automatically — same
                    //     behaviour as before for the failure path.
                    if (_hasTrailer) ...[
                      const SizedBox(width: 10),
                      _HeroButton(
                        icon: Icons.play_circle_outline,
                        label: l10n.watchTrailer,
                        isPrimary: false,
                        onTap: () => _openTrailerExpanded(channel),
                      ),
                    ],
                  ],
                ),

                // Page indicators
                if (widget.channels.length > 1) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(widget.channels.length.clamp(0, 10), (index) {
                      final isActive = index == _currentIndex;
                      return GestureDetector(
                        onTap: () => _goToIndex(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isActive ? 28 : 8,
                          height: 3,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.primary : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Fallback helpers: vodInfo → channel DB data
  String? _plotText(Channel ch) {
    final v = widget.vodInfo?.plot;
    if (v != null && v.isNotEmpty) return v;
    return (ch.plot != null && ch.plot!.isNotEmpty) ? ch.plot : null;
  }

  String? _genreText(Channel ch) {
    final v = widget.vodInfo?.genre;
    if (v != null && v.isNotEmpty) return v;
    return (ch.genre != null && ch.genre!.isNotEmpty) ? ch.genre : null;
  }

  /// Truncate plot text cleanly at word boundary
  String _truncatePlot(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    // Find last space before maxLen to avoid cutting mid-word
    final cutoff = text.lastIndexOf(' ', maxLen);
    return '${text.substring(0, cutoff > 0 ? cutoff : maxLen)}…';
  }

  /// Trailer button is shown for every VOD (movie / series). Even when the
  /// server didn't supply a YouTube id we now fall back to a YouTube search
  /// at the call site (see dashboard_screen._openTrailer + youtube_trailer.dart),
  /// so the affordance is always actionable. Live channels still hide it.
  bool get _hasTrailer {
    return widget.channels[_currentIndex].type != 'live';
  }

  /// Hero image — cached so a slide repeating after the 12s auto-rotate
  /// doesn't re-download the multi-MB backdrop every cycle.
  Widget _buildHeroImage(Channel channel, String? backdropUrl, bool hasBackdrop) {
    final imgUrl = hasBackdrop ? backdropUrl! : channel.streamIcon;
    if (imgUrl != null && imgUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imgUrl,
        key: ValueKey('hero_bg_${channel.streamId}_$imgUrl'),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.3),
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, _, _) => _buildPosterBackground(channel),
      );
    }
    return _buildPosterBackground(channel);
  }

  /// When no backdrop: use poster as full-width blurred background (like movies/series hero)
  Widget _buildPosterBackground(Channel channel) {
    if (channel.streamIcon == null || channel.streamIcon!.isEmpty) {
      return Container(
        key: ValueKey('fallback_${channel.streamId}'),
        color: AppColors.surfaceDark,
      );
    }

    final scaledPoster = Transform.scale(
      scale: 1.2,
      child: CachedNetworkImage(
        imageUrl: channel.streamIcon!,
        fit: BoxFit.cover,
        // Darkened backdrop — no need to decode at full res.
        memCacheWidth: 720,
        errorWidget: (_, _, _) => Container(color: AppColors.surfaceDark),
      ),
    );
    return Stack(
      key: ValueKey('poster_bg_${channel.streamId}'),
      fit: StackFit.expand,
      children: [
        // Poster scaled to cover entire area (like a backdrop). Skip the
        // GPU-heavy gaussian blur on Android TV — weak TV GPUs choke on
        // it; the 45% darken overlay below keeps text readable anyway.
        PlatformHelper.isTV
            ? scaledPoster
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: scaledPoster,
              ),
        // Darken overlay for text readability
        Container(color: Colors.black.withValues(alpha: 0.45)),
      ],
    );
  }

  Widget _buildBadges(Channel channel, AppLocalizations l10n, double? rating) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        // Type badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: channel.type == 'live' ? Colors.red : AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            channel.type == 'live' ? l10n.live : (channel.type == 'movie' ? l10n.movie : l10n.seriesLabel),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
          ),
        ),
        // Year
        if (channel.year != null)
          _badgeChip(channel.year!, Colors.white.withValues(alpha: 0.12), AppColors.textSecondaryDark),
        // IMDb Rating
        if (rating != null && rating > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: AppColors.gold, size: 12),
                const SizedBox(width: 3),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ],
            ),
          ),
        // Duration
        if (widget.vodInfo?.duration != null && widget.vodInfo!.duration!.isNotEmpty)
          _badgeChip(widget.vodInfo!.duration!, Colors.white.withValues(alpha: 0.08), AppColors.textTertiaryDark),
        // Live indicator
        if (channel.type == 'live')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(l10n.live, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 10)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _badgeChip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }
}

// ===========================================================================
//  Hero Button (D-pad + Mouse + Touch)
// ===========================================================================

class _HeroButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  /// External FocusNode — used for the leftmost (Play) button so the
  /// dashboard's branch-primary callback can target it directly via
  /// the focus registry (sidebar → right lands here).
  final FocusNode? focusNode;

  /// Fires on D-pad left. Only set for the leftmost button so the
  /// natural "left out of the button row" gesture lands on the
  /// sidebar instead of falling through to Flutter's default
  /// directional traversal.
  final VoidCallback? onLeftEdge;

  const _HeroButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    this.onTap,
    this.focusNode,
    this.onLeftEdge,
  });

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onTap?.call();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.onLeftEdge != null) {
            widget.onLeftEdge!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: PlatformHelper.useHoverEffects
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: PlatformHelper.useHoverEffects
            ? (_) => setState(() => _isHovered = true)
            : null,
        onExit: PlatformHelper.useHoverEffects
            ? (_) => setState(() => _isHovered = false)
            : null,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: widget.isPrimary
                    ? (isActive ? Colors.white : Colors.white.withValues(alpha: 0.9))
                    : (isActive ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(8),
                border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: widget.isPrimary ? Colors.black : Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.isPrimary ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Fullscreen trailer viewer
//
// Pushed by [_HeroBannerState._openTrailerExpanded] when the user taps
// the muted preview. Opens with a custom transition so the trailer
// scales up from the hero region rather than slide-from-bottom — keeps
// the Netflix tap-to-expand affordance crisp.
//
// The route owns its OWN Player instance (not the hero preview's) so
// the preview can stay alive and resume cleanly on dismiss. Audio is
// unmuted, controls use media_kit's stock material set, and Esc /
// back / X all dismiss.
// ──────────────────────────────────────────────────────────────────────

class _TrailerFullscreenRoute<T> extends PageRoute<T> {
  _TrailerFullscreenRoute({required this.streamUrl, required this.title});

  final String streamUrl;
  final String title;

  @override
  Color? get barrierColor => Colors.black;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => false;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return _TrailerFullscreenView(streamUrl: streamUrl, title: title);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Fade-and-zoom: starts at 92% scale + 0 opacity, ends at 100% /
    // full opaque. Mimics the YouTube tap-to-fullscreen zoom — subtle
    // enough not to nauseate but visible enough to read as "the
    // preview just became the experience".
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final scale = Tween<double>(begin: 0.92, end: 1.0).animate(fade);
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, child: child),
    );
  }
}

class _TrailerFullscreenView extends StatefulWidget {
  const _TrailerFullscreenView({required this.streamUrl, required this.title});

  final String streamUrl;
  final String title;

  @override
  State<_TrailerFullscreenView> createState() => _TrailerFullscreenViewState();
}

class _TrailerFullscreenViewState extends State<_TrailerFullscreenView> {
  late final Player _player;
  late final VideoController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Full volume; the preview was muted by design but the expanded
      // experience is meant to be the actual trailer with audio.
      await _player.setVolume(100);
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.open(Media(widget.streamUrl), play: true);
    } catch (_) {
      // Open failed — close immediately so the user doesn't sit
      // staring at a black screen.
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Esc / back closes the route. CallbackShortcuts is the cheapest
    // way to bind Esc on desktop without pulling in a Focus tree.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Trailer video — Material controls (play/pause, seek,
              // volume, time). media_kit's stock controls are good
              // enough that we don't need a bespoke skin for an
              // ephemeral preview.
              Positioned.fill(
                child: _ready
                    ? Video(
                        controller: _controller,
                        fit: BoxFit.contain,
                        controls: AdaptiveVideoControls,
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
              ),

              // Title strip — small subtle label so the user knows
              // which trailer they're watching even after the
              // controls auto-hide.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 80, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),

              // Close button — top-right, large hit target. Mirrors
              // the position of the "Fragmanı izle" badge so the eye
              // returns to where the action started.
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
