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

  /// On Android TV, collapse focus/transition animations to nothing. The
  /// 10-foot UI must stay snappy on weak TV GPUs — the focus ring/border is
  /// the affordance, motion isn't worth the per-frame cost. Use [focusAnim]
  /// for the common 150 ms focus tween, or [anim] to scale any duration.
  static bool get noAnimations => isTV;

  /// 150 ms focus tween off-TV, instant on TV. Drop-in for the many
  /// `AnimatedContainer(duration: 150ms)` focus borders across the app.
  static Duration get focusAnim =>
      isTV ? Duration.zero : const Duration(milliseconds: 150);

  /// Scale any animation duration: zero on TV, [d] elsewhere.
  static Duration anim(Duration d) => isTV ? Duration.zero : d;

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
    // Mobile — phones get 3 columns so posters aren't huge (only ~4
    // fit a screen at 2 cols). Large phones / small tablets get 4;
    // only very narrow devices fall back to 2.
    if (screenWidth > 600) return 4;
    if (screenWidth >= 340) return 3;
    return 2;
  }

  /// Sidebar width based on platform
  static double get sidebarCollapsedWidth => isTV ? 72 : 64;
  static double get sidebarExpandedWidth => isTV ? 220 : 200;

  /// Card sizes
  static double get posterAspectRatio => 0.65;
  static double get landscapeAspectRatio => 16 / 9;

  // ── Focus ring (TV mode reads from 3m, desktop reads from arm's length) ─
  //
  // TV remotes don't show a mouse cursor, so the focus ring IS the
  // only "where am I" signal — it needs to be loud. Desktop has the
  // cursor + a more typical Netflix-style subtle ring.

  /// Border thickness drawn around the focused card / row / item.
  static double get focusRingWidth => isTV ? 3.5 : 2.0;

  /// Multiplier applied to the focused card's scale. Desktop is a
  /// gentle 1.08; TV bumps to 1.12 so the size pop is visible from
  /// a couch.
  static double get focusedScale => isTV ? 1.12 : 1.08;

  /// Blur radius for the glow shadow behind a focused card. TV emits
  /// a stronger halo; desktop keeps it tight.
  static double get focusRingGlowBlur => isTV ? 24.0 : 14.0;

  /// Alpha 0–1 for the glow color (primary at this opacity).
  static double get focusRingGlowAlpha => isTV ? 0.55 : 0.30;
}
