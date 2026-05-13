/// Cross-screen focus dispatch for D-pad navigation.
///
/// `StatefulShellRoute.indexedStack` puts the sidebar and the active branch
/// in sibling subtrees, so the sidebar can't reach the active screen with
/// `findAncestorStateOfType` or `nextFocus`. Instead, screens register a
/// "primary focus" callback for their branch when mounted; the sidebar
/// asks the registry to fire that callback when the user presses right.
///
/// The registry is plain mutable state — a DI-style service, not Riverpod
/// notifier state. Callbacks change frequently as widgets mount/unmount;
/// publishing those changes as immutable snapshots would trigger pointless
/// rebuilds across the app. Provide it as `Provider<TvFocusRegistry>` so
/// the same instance is shared without rebuild semantics.
typedef VoidFocusCallback = void Function();

class TvFocusRegistry {
  TvFocusRegistry();

  // Sidebar focus — top-level, single slot. The AppSidebar registers its
  // "focus current menu item" callback here on mount.
  VoidFocusCallback? _focusMainSidebar;

  // Branch primary focus targets. Keyed by branch index so the same screen
  // can re-register across hot reloads or branch swaps without leaking.
  final Map<int, VoidFocusCallback> _branchPrimary = {};

  // Overlay primary — a layered focus target that takes priority over the
  // branch's primary while present. Detail views push their "play button"
  // or "back button" callback here; popping it restores the branch as the
  // default target.
  VoidFocusCallback? _overlayPrimary;

  // ── Main sidebar ─────────────────────────────────────────────────────

  void registerMainSidebar(VoidFocusCallback cb) {
    _focusMainSidebar = cb;
  }

  /// Idempotent unregister. The identity check prevents a late unregister
  /// from a previously-mounted sidebar wiping a newer registration during
  /// hot reload.
  void unregisterMainSidebar(VoidFocusCallback cb) {
    if (identical(_focusMainSidebar, cb)) {
      _focusMainSidebar = null;
    }
  }

  /// Focus the main sidebar. Returns false if nothing is registered yet
  /// (e.g. during very first frame); caller can decide whether to fall
  /// back to `focusInDirection` or no-op.
  bool requestMainSidebar() {
    final cb = _focusMainSidebar;
    if (cb == null) return false;
    cb();
    return true;
  }

  // ── Branch primary (the active screen's "main content" focus) ────────

  void registerBranchPrimary(int branchIndex, VoidFocusCallback cb) {
    _branchPrimary[branchIndex] = cb;
  }

  void unregisterBranchPrimary(int branchIndex, VoidFocusCallback cb) {
    if (identical(_branchPrimary[branchIndex], cb)) {
      _branchPrimary.remove(branchIndex);
    }
  }

  /// Focus the active screen's primary content. Prefers an overlay target
  /// (e.g. detail view) when one is pushed, otherwise the branch primary.
  /// Returns false when neither is available.
  bool requestActivePrimary(int branchIndex) {
    final overlay = _overlayPrimary;
    if (overlay != null) {
      overlay();
      return true;
    }
    final cb = _branchPrimary[branchIndex];
    if (cb == null) return false;
    cb();
    return true;
  }

  // ── Overlay (detail / modal layered on top of a branch) ──────────────

  /// Push an overlay focus target. Currently we only need a single slot;
  /// nested overlays (modal within a detail) can be added later.
  void pushOverlayPrimary(VoidFocusCallback cb) {
    _overlayPrimary = cb;
  }

  void popOverlayPrimary(VoidFocusCallback cb) {
    if (identical(_overlayPrimary, cb)) {
      _overlayPrimary = null;
    }
  }
}
