import 'dart:async';

import 'package:flutter/material.dart';

/// One-shot branded splash, shown over the whole app on cold start.
///
/// Platform-agnostic (pure Flutter), so it gives Android mobile, Windows
/// and Linux desktop the same premium launch as the Android TV banner:
/// the white LifeOS mark on a dark gradient, the "LifeOS Tv" wordmark, and
/// the "By Erkan ÖZ" signature.
///
/// It lives as the top child of the root [Stack] in `main.dart`'s
/// `MaterialApp.router` builder — no router changes. It fades in, holds,
/// fades out, then renders nothing (and stops intercepting input) for the
/// rest of the process lifetime. Its [State] persists across the builder's
/// rebuilds (keyed), so it plays exactly once.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key});

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash> {
  bool _visible = true; // fade target
  bool _gone = false; // fully removed from the tree
  Timer? _holdTimer;
  Timer? _removeTimer;

  static const _fade = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    // Hold ~1.4s after first frame, fade out, then drop entirely.
    _holdTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _visible = false);
    });
    _removeTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: _fade,
        curve: Curves.easeOut,
        child: const _BrandSplashContent(),
      ),
    );
  }
}

class _BrandSplashContent extends StatefulWidget {
  const _BrandSplashContent();

  @override
  State<_BrandSplashContent> createState() => _BrandSplashContentState();
}

class _BrandSplashContentState extends State<_BrandSplashContent>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFFE5484D);
  static const _subtitle = Color(0xFFB6BECA);
  static const _byDim = Color(0xFF788090);
  static const _byName = Color(0xFFD69698);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<double> _scale =
      Tween<double>(begin: 0.92, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.of(context).size.shortestSide;
    final markH = (shortest * 0.24).clamp(110.0, 240.0);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161C2C), Color(0xFF08090F)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft red spotlight behind the mark.
          Container(
            width: markH * 2.4,
            height: markH * 2.4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_accent.withValues(alpha: 0.16), Colors.transparent],
              ),
            ),
          ),
          FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/app_logo_mark_white.png',
                    height: markH,
                    filterQuality: FilterQuality.high,
                  ),
                  SizedBox(height: markH * 0.16),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: markH * 0.26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        height: 1.0,
                      ),
                      children: const [
                        TextSpan(
                          text: 'LifeOS ',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Tv',
                          style: TextStyle(color: _accent),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: markH * 0.10),
                  Text(
                    'IPTV • Movies • Series • Live',
                    style: TextStyle(
                      color: _subtitle,
                      fontSize: markH * 0.085,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(height: markH * 0.16),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: markH * 0.075,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                      children: const [
                        TextSpan(text: 'By ', style: TextStyle(color: _byDim)),
                        TextSpan(
                          text: 'Erkan ÖZ',
                          style: TextStyle(color: _byName),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
