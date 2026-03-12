import 'dart:io';
import 'package:flutter/foundation.dart';

/// Platform detection helper for adaptive UI
class PlatformHelper {
  static bool get isTV {
    // Android TV detection - check if running on TV device
    if (Platform.isAndroid) {
      // Will be true on Android TV devices
      return _isTVDevice;
    }
    return false;
  }

  static bool _isTVDevice = false;

  /// Call this during app initialization from native code
  static void setTVDevice(bool isTV) {
    _isTVDevice = isTV;
  }

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !isTV;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Whether to use D-pad/remote focus navigation
  static bool get useDpadNavigation => isTV;

  /// Whether to show mouse-hover effects
  static bool get useHoverEffects => isDesktop;

  /// Whether to use touch gestures
  static bool get useTouchGestures => isMobile;

  /// Grid column count based on screen type
  static int gridColumns(double screenWidth) {
    if (isTV) {
      if (screenWidth > 1600) return 7;
      if (screenWidth > 1200) return 6;
      return 5;
    }
    if (isDesktop) {
      if (screenWidth > 1600) return 7;
      if (screenWidth > 1200) return 6;
      if (screenWidth > 900) return 5;
      return 4;
    }
    // Mobile
    if (screenWidth > 600) return 4;
    if (screenWidth > 400) return 3;
    return 2;
  }

  /// Sidebar width based on platform
  static double get sidebarCollapsedWidth => isTV ? 72 : 64;
  static double get sidebarExpandedWidth => isTV ? 220 : 200;

  /// Card sizes
  static double get posterAspectRatio => 0.65;
  static double get landscapeAspectRatio => 16 / 9;
}
