import 'package:flutter/widgets.dart';

/// Imperative focus controller for a virtualized poster grid.
///
/// `GridView.builder` only mounts items currently in (or near) the
/// viewport. A naive `FocusNode.requestFocus()` for an off-screen
/// streamId would silently no-op because no node exists yet. The
/// controller pairs an in-memory index (streamIds + layout snapshot)
/// with a scroll-then-retry mechanism so callers can write code like
/// `controller.focusByStreamId(123)` and have it Just Work whether the
/// target is in viewport or 50 rows below.
///
/// Ownership:
/// - The screen creates one of these per poster grid and outlives the
///   grid across detail-view pushes (so streamId memory survives).
/// - `TvPosterGrid` calls [attach] in build (with current layout
///   metrics + the visible streamIds) and [detach] in dispose.
/// - Each mounted poster item calls [registerItem] in initState and
///   [unregisterItem] in dispose with its own FocusNode.
class TvPosterGridController {
  /// streamId → FocusNode for items currently mounted in the viewport
  /// or scroll cache. Items outside that window are absent and any
  /// `focusByStreamId` for them takes the scroll-and-retry path.
  final Map<int, FocusNode> _nodes = {};

  /// Ordered list of streamIds the grid is rendering. The order
  /// determines D-pad arithmetic (left/right/up/down in row-major).
  List<int> _streamIds = const [];

  /// The grid's ScrollController. Null while detached.
  ScrollController? _scrollController;

  /// Layout snapshot for index→pixel-offset conversion. The widget
  /// computes these from constraints and pushes them via [attach].
  int _columns = 1;
  double _rowStride = 0; // tile height + main-axis spacing between rows
  double _paddingTop = 0;

  /// streamId of the most recently focused poster, or -1 if none. Used
  /// by callers to restore focus after a detail view closes.
  int _lastFocusedStreamId = -1;

  // ── Lifecycle: widget ↔ controller ──────────────────────────────────

  void attach({
    required ScrollController scrollController,
    required int columns,
    required double rowStride,
    required double paddingTop,
    required List<int> streamIds,
  }) {
    _scrollController = scrollController;
    _columns = columns < 1 ? 1 : columns;
    _rowStride = rowStride;
    _paddingTop = paddingTop;
    _streamIds = streamIds;
  }

  void detach(ScrollController scrollController) {
    if (identical(_scrollController, scrollController)) {
      _scrollController = null;
    }
  }

  // ── Lifecycle: items ↔ controller ───────────────────────────────────

  void registerItem(int streamId, FocusNode node) {
    _nodes[streamId] = node;
  }

  void unregisterItem(int streamId, FocusNode node) {
    if (identical(_nodes[streamId], node)) {
      _nodes.remove(streamId);
    }
  }

  /// Called by an item when it gains focus. Updates the restore target.
  void notifyFocused(int streamId) {
    _lastFocusedStreamId = streamId;
  }

  // ── Read-only state ─────────────────────────────────────────────────

  int get lastFocusedStreamId => _lastFocusedStreamId;
  int get columns => _columns;
  int get itemCount => _streamIds.length;
  List<int> get streamIds => List.unmodifiable(_streamIds);
  bool get hasScrollController => _scrollController != null;

  // ── Focus API ───────────────────────────────────────────────────────

  /// Focus the first poster. Returns false only if the grid is empty.
  /// Synchronous for mounted items; async-retried for unmounted ones.
  bool focusFirst() {
    if (_streamIds.isEmpty) return false;
    return focusIndex(0);
  }

  /// Focus the most recently focused poster if it still exists in the
  /// current list; otherwise the first item. The intended entry point
  /// when closing a detail view: caller doesn't need to remember which
  /// streamId was focused, the controller tracks it.
  bool focusCurrentOrFirst() {
    if (_lastFocusedStreamId >= 0 &&
        _streamIds.contains(_lastFocusedStreamId)) {
      return focusByStreamId(_lastFocusedStreamId);
    }
    return focusFirst();
  }

  /// Focus the poster matching [streamId] in the current list. Returns
  /// false if the streamId is not in the current ordered list (e.g.
  /// filter changed and that item dropped out); true if the request was
  /// accepted, even when the actual focus delivery is deferred to a
  /// post-frame because the item must be scrolled into view first.
  bool focusByStreamId(int streamId) {
    final index = _streamIds.indexOf(streamId);
    if (index < 0) return false;
    return focusIndex(index);
  }

  /// Focus the poster at [index] in the current list. See [focusByStreamId]
  /// for the success semantics.
  bool focusIndex(int index) {
    if (index < 0 || index >= _streamIds.length) return false;
    final streamId = _streamIds[index];
    final mountedNode = _nodes[streamId];
    if (mountedNode != null && mountedNode.canRequestFocus) {
      mountedNode.requestFocus();
      return true;
    }
    // Item is not mounted: scroll into approximate position, then look
    // again on the next frame. Two retries cover the common case where
    // GridView builds in two passes (initial layout, then with the new
    // viewport).
    _scrollToIndex(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocus(streamId, attemptsLeft: 2);
    });
    return true;
  }

  void _retryFocus(int streamId, {required int attemptsLeft}) {
    final node = _nodes[streamId];
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
      return;
    }
    if (attemptsLeft <= 0) {
      // Final fallback: pick the first mounted node, even if it's not
      // the one the caller asked for. Better than leaving focus dangling
      // in the sidebar or detail view.
      for (final id in _streamIds) {
        final n = _nodes[id];
        if (n != null && n.canRequestFocus) {
          n.requestFocus();
          return;
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocus(streamId, attemptsLeft: attemptsLeft - 1);
    });
  }

  /// Approximate-scroll the grid so the row containing [index] is in
  /// view. Once the item mounts, its onFocusChange handler will run
  /// `Scrollable.ensureVisible` for precise alignment.
  void _scrollToIndex(int index) {
    final scroll = _scrollController;
    if (scroll == null || !scroll.hasClients) return;
    if (_rowStride <= 0) return;
    final rowIndex = index ~/ _columns;
    final viewport = scroll.position.viewportDimension;
    // Aim to center the row in the viewport — better TV ergonomics than
    // top-aligning.
    final targetOffset = _paddingTop +
        rowIndex * _rowStride -
        viewport / 2 +
        _rowStride / 2;
    final clamped =
        targetOffset.clamp(0.0, scroll.position.maxScrollExtent).toDouble();
    scroll.jumpTo(clamped);
  }
}
