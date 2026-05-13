/// What [AppShell] should do in response to a back press, computed
/// from the current state without performing any side effects. Pulled
/// out of `_handleBack` so the decision ladder can be unit-tested
/// without standing up a full navigation shell + Riverpod tree.
enum AppShellBackAction {
  /// The active screen's custom back handler claimed the press — the
  /// shell does nothing further.
  consumed,

  /// Bounce focus to the main sidebar. Only emitted on platforms that
  /// use the sidebar layout (desktop / Android TV) when the sidebar
  /// exists but doesn't already hold focus.
  focusSidebar,

  /// Navigate to the Dashboard branch (index 0). Reached when focus is
  /// on the sidebar of a non-Dashboard branch, or on mobile without a
  /// sidebar bounce step.
  goToDashboard,

  /// First back press inside the 2s window on Dashboard with the
  /// sidebar focused — show "press back again to exit" feedback.
  showExitConfirm,

  /// Second back press within 2s — exit the app.
  exit,
}

/// Pure decision function. All Boolean inputs reflect external state
/// at the moment of the press; the function never reads from
/// FocusManager, Navigator, or Riverpod directly. Keep this in sync
/// with [AppShell._handleBack].
AppShellBackAction resolveAppShellBackAction({
  required bool screenHandlerHandled,
  required bool isDesktopPlatform,
  required bool sidebarMounted,
  required bool sidebarHasFocus,
  required int currentBranchIndex,
  required DateTime? lastBackPress,
  required DateTime now,
  Duration exitConfirmWindow = const Duration(seconds: 2),
}) {
  if (screenHandlerHandled) return AppShellBackAction.consumed;

  // Step 1: desktop/TV sidebar bounce. Mobile (no persistent sidebar)
  // skips this and falls through to branch logic.
  if (isDesktopPlatform && sidebarMounted && !sidebarHasFocus) {
    return AppShellBackAction.focusSidebar;
  }

  // Step 2: back from any branch's sidebar surfaces the root.
  if (currentBranchIndex != 0) {
    return AppShellBackAction.goToDashboard;
  }

  // Step 3: Dashboard + sidebar focused. Exit-confirm dance.
  if (lastBackPress != null && now.difference(lastBackPress) < exitConfirmWindow) {
    return AppShellBackAction.exit;
  }
  return AppShellBackAction.showExitConfirm;
}
