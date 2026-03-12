import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

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

class HeroBanner extends StatefulWidget {
  final List<Channel> channels;
  final Function(Channel)? onPlay;
  final Function(Channel)? onDetails;
  final Function(Channel)? onTrailer;

  /// Called when hero item changes - parent should fetch VOD info
  final Function(Channel)? onItemChanged;

  /// Current VOD info for the active hero item
  final HeroVodInfo? vodInfo;

  const HeroBanner({
    super.key,
    required this.channels,
    this.onPlay,
    this.onDetails,
    this.onTrailer,
    this.onItemChanged,
    this.vodInfo,
  });

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _currentIndex = 0;
  Timer? _autoSlideTimer;
  int _lastChannelCount = 0;

  bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 600;

  @override
  void initState() {
    super.initState();
    _lastChannelCount = widget.channels.length;
    _startAutoSlide();
    // Notify parent of initial item
    if (widget.channels.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onItemChanged?.call(widget.channels[0]);
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
      // Notify parent of current item after channels changed
      if (widget.channels.isNotEmpty) {
        widget.onItemChanged?.call(widget.channels[_currentIndex]);
      }
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    if (widget.channels.length > 1) {
      _autoSlideTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          final newIndex = (_currentIndex + 1) % widget.channels.length;
          setState(() => _currentIndex = newIndex);
          widget.onItemChanged?.call(widget.channels[newIndex]);
        }
      });
    }
  }

  void _goToIndex(int index) {
    if (index == _currentIndex || index < 0 || index >= widget.channels.length) return;
    setState(() => _currentIndex = index);
    widget.onItemChanged?.call(widget.channels[index]);
    _startAutoSlide(); // Reset timer
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

    // Same height as movies/series hero — proven to work well
    final clampedHeight = mobile ? 200.0 : 280.0;

    if (widget.channels.isEmpty) {
      return SizedBox(
        height: clampedHeight,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.movie_outlined, size: 48, color: AppColors.textTertiaryDark),
              const SizedBox(height: 12),
              Text(l10n.noChannels, style: TextStyle(color: AppColors.textSecondaryDark)),
            ],
          ),
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

          // ── Left gradient (same as movies hero) ──
          Container(decoration: BoxDecoration(
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

          // ── Bottom gradient (same as movies hero) ──
          Container(decoration: BoxDecoration(
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
                    ),
                    const SizedBox(width: 10),
                    _HeroButton(
                      icon: Icons.info_outline,
                      label: l10n.details,
                      isPrimary: false,
                      onTap: () => widget.onDetails?.call(channel),
                    ),
                    // Trailer button (if available)
                    if (_hasTrailer) ...[
                      const SizedBox(width: 10),
                      _HeroButton(
                        icon: Icons.play_circle_outline,
                        label: l10n.watchTrailer,
                        isPrimary: false,
                        onTap: () => widget.onTrailer?.call(channel),
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

  String? _directorText(Channel ch) {
    final v = widget.vodInfo?.director;
    if (v != null && v.isNotEmpty) return v;
    return (ch.director != null && ch.director!.isNotEmpty) ? ch.director : null;
  }

  /// Truncate plot text cleanly at word boundary
  String _truncatePlot(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    // Find last space before maxLen to avoid cutting mid-word
    final cutoff = text.lastIndexOf(' ', maxLen);
    return '${text.substring(0, cutoff > 0 ? cutoff : maxLen)}…';
  }

  bool get _hasTrailer {
    final t = widget.vodInfo?.youtubeTrailer ?? widget.channels[_currentIndex].youtubeTrailer;
    return t != null && t.isNotEmpty;
  }

  /// Hero image — same approach as movies/series hero: Image.network + BoxFit.cover
  Widget _buildHeroImage(Channel channel, String? backdropUrl, bool hasBackdrop) {
    final imgUrl = hasBackdrop ? backdropUrl! : channel.streamIcon;
    if (imgUrl != null && imgUrl.isNotEmpty) {
      return Image.network(
        imgUrl,
        key: ValueKey('hero_bg_${channel.streamId}_$imgUrl'),
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.3),
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildPosterBackground(channel),
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

    return Stack(
      key: ValueKey('poster_bg_${channel.streamId}'),
      fit: StackFit.expand,
      children: [
        // Poster scaled to cover entire area (like a backdrop)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Transform.scale(
            scale: 1.2,
            child: CachedNetworkImage(
              imageUrl: channel.streamIcon!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: AppColors.surfaceDark),
            ),
          ),
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

  const _HeroButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    this.onTap,
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
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
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
