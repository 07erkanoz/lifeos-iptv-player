import 'package:flutter/material.dart';
import 'package:lifeostv/core/platform_helper.dart';

/// Responsive layout utilities via BuildContext extensions.
/// Uses screen width for layout decisions (not platform detection),
/// so Android tablets get appropriate layouts too.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Phone-sized screens (<600dp)
  bool get isMobileWidth => screenWidth < 600;

  /// Tablet-sized screens (600-1024dp)
  bool get isTabletWidth => screenWidth >= 600 && screenWidth < 1024;

  /// Desktop-sized screens (>=1024dp)
  bool get isDesktopWidth => screenWidth >= 1024;

  /// Dynamic grid column count based on screen width + platform
  /// Mobile: 2-3, Tablet: 4, Desktop: 5-7
  int get gridColumns => PlatformHelper.gridColumns(screenWidth);

  /// Horizontal padding — tighter on mobile
  double get horizontalPadding => isMobileWidth ? 12.0 : 24.0;

  /// Title font size
  double get titleFontSize => isMobileWidth ? 18.0 : 28.0;

  /// Subtitle font size
  double get subtitleFontSize => isMobileWidth ? 12.0 : 14.0;

  /// Content carousel height
  double get carouselHeight => isMobileWidth ? 200.0 : 260.0;

  /// Poster card dimensions
  double get posterWidth => isMobileWidth ? 120.0 : 150.0;
  double get posterHeight => isMobileWidth ? 180.0 : 220.0;
}
