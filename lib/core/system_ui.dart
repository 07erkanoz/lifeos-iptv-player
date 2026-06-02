import 'package:flutter/services.dart';
import 'package:lifeostv/core/platform_helper.dart';

/// Single source of truth for the app-level Android system UI mode.
///
/// Two call sites used to set this independently and drift out of
/// sync:
///   * main.dart applied `manual + [bottom]` (hide status bar, keep
///     the gesture/nav bar) when the user's fullscreen toggle was on,
///     `edgeToEdge` otherwise.
///   * The video player forced `immersiveSticky` on entry and then
///     **unconditionally** restored `edgeToEdge` on exit — wiping the
///     user's fullscreen preference every time they watched something.
///
/// On top of that, nothing re-applied the mode when the app came back
/// from the background: Android restores the system bars on resume, so
/// the status bar "leaked" back in even with fullscreen on.
///
/// Routing every app-level change through [applyMobileSystemUiMode]
/// (and re-applying it on resume + on player exit) keeps the bar state
/// sticky. The player still uses its own `immersiveSticky` while video
/// is on screen; it just calls this helper on the way out instead of
/// hardcoding `edgeToEdge`.
void applyMobileSystemUiMode({required bool fullscreen}) {
  if (!PlatformHelper.isMobile) return;
  if (fullscreen) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom], // keep gesture / nav bar
    );
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
