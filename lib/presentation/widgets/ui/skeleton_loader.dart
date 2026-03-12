import 'package:flutter/material.dart';
import 'package:lifeostv/config/theme.dart';

/// Shimmer-effect skeleton loading placeholder
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_shimmer.value - 1, 0),
            end: Alignment(_shimmer.value, 0),
            colors: [
              AppColors.surfaceDark,
              AppColors.surfaceElevatedDark,
              AppColors.surfaceDark,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for a poster card in grid
class SkeletonPoster extends StatelessWidget {
  const SkeletonPoster({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonLoader(width: double.infinity, height: double.infinity, borderRadius: 8);
  }
}

/// Skeleton for hero banner
class SkeletonHero extends StatelessWidget {
  const SkeletonHero({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonLoader(width: double.infinity, height: 400, borderRadius: 0);
  }
}

/// Skeleton for a horizontal content row
class SkeletonRow extends StatelessWidget {
  final int count;
  final double itemWidth;
  final double itemHeight;

  const SkeletonRow({
    super.key,
    this.count = 6,
    this.itemWidth = 140,
    this.itemHeight = 210,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => SkeletonLoader(width: itemWidth, height: itemHeight),
      ),
    );
  }
}
