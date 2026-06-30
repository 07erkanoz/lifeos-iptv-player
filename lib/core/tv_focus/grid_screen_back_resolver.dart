/// Outcome of a back press inside a Movies-style "main sidebar +
/// category panel + grid + optional detail" screen.
///
/// The same decision applies to Movies and Series (and any future
/// screen with that layout), so the logic lives in one tested
/// function rather than being duplicated in each screen's
/// `_registerBackHandler`.
enum GridScreenBackAction {
  /// Detail view is open — the screen should close it. Consumes the
  /// press.
  closeDetail,

  /// Focus is on the grid (or anywhere inside the screen that isn't a
  /// modal we own) and the category panel is open — bounce focus to
  /// the category panel. Consumes the press.
  bounceToCategory,

  /// Nothing more for this screen to do — return false from the
  /// back handler so AppShell can run its outer ladder
  /// (focus main sidebar, navigate to Dashboard, exit dance).
  handToShell,
}

GridScreenBackAction resolveGridScreenBackAction({
  required bool detailOpen,
  required bool mainSidebarFocused,
  required bool categoriesCollapsed,
  required bool categoryScopeFocused,
  // True when this screen has an inline category panel that can hold focus
  // (TV / desktop). False on mobile, where categories are a bottom sheet,
  // so a collapsed state should just hand back to the shell.
  bool categoryPanelAvailable = true,
}) {
  // 1. Detail wins over everything — Esc / Back closes it.
  if (detailOpen) return GridScreenBackAction.closeDetail;

  // 2. Already on the main sidebar → AppShell handles "go to
  // Dashboard" or the exit dance.
  if (mainSidebarFocused) return GridScreenBackAction.handToShell;

  // 3. On the category panel → one step further out (main sidebar)
  // is AppShell's job.
  if (!categoriesCollapsed && categoryScopeFocused) {
    return GridScreenBackAction.handToShell;
  }

  // 4. Focus is in the grid / hero / toolbar with the category panel
  // open → bounce one zone outward to the category panel.
  if (!categoriesCollapsed) return GridScreenBackAction.bounceToCategory;

  // 5. Category panel is collapsed. On TV/desktop the panel IS the
  // intermediate zone — re-open it (the ladder is grid → category panel
  // → main sidebar). Only when there's no such panel (mobile) do we hand
  // straight to the shell.
  if (categoryPanelAvailable) return GridScreenBackAction.bounceToCategory;
  return GridScreenBackAction.handToShell;
}
