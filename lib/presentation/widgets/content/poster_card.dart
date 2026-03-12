import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class PosterCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final double width;
  final double height;
  final bool showNewBadge;

  const PosterCard({
    super.key,
    required this.channel,
    this.onTap,
    this.onFocus,
    this.width = 150,
    this.height = 220,
    this.showNewBadge = false,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> with SingleTickerProviderStateMixin {
  static const double _hoverScale = 1.02;
  static const double _hoverLift = -6;
  static const double _hoverInset = 8;

  bool _isFocused = false;
  bool _isHovered = false;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _liftAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: _hoverScale).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
    _liftAnimation = Tween<double>(begin: 0, end: _hoverLift).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _setActive(bool active) {
    if (active) {
      if (_scaleController.status != AnimationStatus.forward &&
          _scaleController.status != AnimationStatus.completed) {
        _scaleController.forward();
      }
    } else {
      if (_scaleController.status != AnimationStatus.reverse &&
          _scaleController.status != AnimationStatus.dismissed) {
        _scaleController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isFocused || _isHovered;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.borderDark,
          width: 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image or Placeholder
            widget.channel.streamIcon != null && widget.channel.streamIcon!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: widget.channel.streamIcon!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildShimmer(),
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),

            // Bottom gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha:0.8),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            // Title
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Text(
                widget.channel.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Type badge (top-left)
            Positioned(
              top: 8,
              left: 8,
              child: Row(
                children: [
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeBadgeColor(widget.channel.type),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _typeBadgeLabel(widget.channel.type),
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  ),
                  // Year badge
                  if (widget.channel.year != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        widget.channel.year!,
                        style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Rating badge (top-right)
            if (widget.channel.rating != null && widget.channel.rating! > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: AppColors.gold, size: 10),
                      const SizedBox(width: 2),
                      Text(
                        widget.channel.rating!.toStringAsFixed(1),
                        style: const TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),

            // New episodes badge
            if (widget.showNewBadge)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.newLabel ?? 'NEW',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Focus(
      onFocusChange: (focused) {
        if (_isFocused != focused) {
          setState(() => _isFocused = focused);
        }
        _setActive(focused || _isHovered);
        if (focused) {
          widget.onFocus?.call();
          // Auto-scroll to show focused card (D-pad/keyboard navigation)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.3,
                duration: const Duration(milliseconds: 200),
              );
            }
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (_isHovered) return;
          setState(() => _isHovered = true);
          _setActive(true);
          widget.onFocus?.call();
        },
        onExit: (_) {
          if (!_isHovered) return;
          setState(() => _isHovered = false);
          _setActive(_isFocused);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.width + (_hoverInset * 2),
            height: widget.height + (_hoverInset * 2),
            child: Center(
              child: AnimatedBuilder(
                animation: _scaleController,
                child: RepaintBoundary(child: card),
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _liftAnimation.value),
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    alignment: Alignment.center,
                    transformHitTests: false,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _typeBadgeColor(String type) {
    switch (type) {
      case 'live': return Colors.red.shade700;
      case 'movie': return Colors.blue.shade700;
      case 'series': return Colors.purple.shade700;
      default: return Colors.grey.shade700;
    }
  }

  String _typeBadgeLabel(String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'live': return l10n?.live ?? 'LIVE';
      case 'movie': return l10n?.movie ?? 'MOVIE';
      case 'series': return l10n?.seriesLabel ?? 'SERIES';
      default: return type.toUpperCase();
    }
  }

  Widget _buildShimmer() {
    return Container(
      color: AppColors.surfaceElevatedDark,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    final name = widget.channel.name;
    final initials = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();

    return Container(
      color: AppColors.surfaceElevatedDark,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: AppColors.textTertiaryDark,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
