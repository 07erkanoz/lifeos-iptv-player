/// Outcome of a back press inside the Live TV screen, computed
/// from the current state without performing any side effects.
///
/// Live TV's structure differs from Movies/Series:
/// - There's no "detail" overlay layer (channels play directly).
/// - There IS an EPG overlay/timeline that's a separate focus zone
///   from the channel list.
/// - Categories panel exists, same as Movies.
///
/// The natural back ladder is:
///   EPG focused          → focus channel list
///   channel list focused → open/focus categories panel
///   categories focused   → AppShell takes over (main sidebar)
///   another content node → open/focus categories panel
enum LiveTvBackAction {
  /// Currently focused on a program in the EPG timeline → focus the
  /// channel list cell of the same channel. Consumes the press.
  focusChannelList,

  /// Focused on the channel list and the categories panel is open →
  /// move focus to the categories panel. Consumes the press.
  focusCategorySidebar,

  /// Nothing more for the Live TV screen to do. Returning false from
  /// the back handler lets AppShell run its outer ladder (focus the
  /// main sidebar, navigate to Dashboard, or run the exit dance).
  handToShell,
}

LiveTvBackAction resolveLiveTvBackAction({
  required bool mainSidebarFocused,
  required bool categoriesCollapsed,
  required bool categoryScopeFocused,
  required bool epgFocused,
  required bool channelListFocused,
}) {
  // 1. Already on the main sidebar → AppShell handles "go to
  // Dashboard" or the exit dance.
  if (mainSidebarFocused) return LiveTvBackAction.handToShell;

  // 2. On the category panel → AppShell moves us further out to the
  // main sidebar.
  if (!categoriesCollapsed && categoryScopeFocused) {
    return LiveTvBackAction.handToShell;
  }

  // 3. EPG focused → step outward to the channel list (one zone
  // closer to the navigation).
  if (epgFocused) return LiveTvBackAction.focusChannelList;

  // 4. Channel list focused + category panel available → step into
  // the panel.
  if (channelListFocused) {
    return LiveTvBackAction.focusCategorySidebar;
  }

  // 5. Returning from the player can leave focus on a transient content
  // node while the list rebuilds. Keep the category layer in the ladder.
  return LiveTvBackAction.focusCategorySidebar;
}
