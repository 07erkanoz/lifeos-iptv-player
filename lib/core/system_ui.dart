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
    // `immersiveSticky` is the only mode that reliably hides the
    // status bar across OEM skins. The earlier `manual + [bottom]`
    // (hide status bar, keep the nav bar) was silently ignored on
    // Huawei / HarmonyOS — the status strip stayed pinned at the top.
    // immersiveSticky hides BOTH bars and auto-reveals them on an edge
    // swipe, then re-hides — the standard fullscreen-media behaviour,
    // consistent on Huawei/Xiaomi/Samsung alike.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
