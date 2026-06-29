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

  /// Deferred-focus intent. On a slow TV, switching category swaps the
  /// grid to a freshly-built widget whose async data + item FocusNodes
  /// land several frames later than the 2-frame retry window. Instead
  /// of dropping focus, we remember the intent here and fulfil it from
  /// [attach] (when the streamIds arrive) or [registerItem] (when the
  /// target poster finally mounts).
  bool _pendingFocusFirst = false;
  int _pendingFocusStreamId = -1;

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
    // The data a deferred focus was waiting on may have just arrived.
    if ((_pendingFocusFirst || _pendingFocusStreamId >= 0) &&
        streamIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingFocusStreamId >= 0 &&
            _streamIds.contains(_pendingFocusStreamId)) {
          final id = _pendingFocusStreamId;
          _pendingFocusStreamId = -1;
          _pendingFocusFirst = false;
          focusByStreamId(id);
        } else if (_pendingFocusFirst) {
          _pendingFocusFirst = false;
          _pendingFocusStreamId = -1;
          focusFirst();
        }
      });
    }
  }

  void detach(ScrollController scrollController) {
    if (identical(_scrollController, scrollController)) {
      _scrollController = null;
    }
  }

  // ── Lifecycle: items ↔ controller ───────────────────────────────────

  void registerItem(int streamId, FocusNode node) {
    _nodes[streamId] = node;
    // Fulfil a deferred focus the moment its target (or, for a
    // first-item request, the first poster) actually mounts.
    if (!node.canRequestFocus) return;
    if (_pendingFocusStreamId == streamId) {
      _pendingFocusStreamId = -1;
      _pendingFocusFirst = false;
      node.requestFocus();
    } else if (_pendingFocusFirst &&
        _streamIds.isNotEmpty &&
        streamId == _streamIds.first) {
      _pendingFocusFirst = false;
      node.requestFocus();
    }
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

  /// Focus the first poster. Returns true only when focus actually
  /// moved (or was synchronously requested); false when there is
  /// nothing to focus right now.
  ///
  /// An empty grid is usually data-not-loaded-yet (slow TV / async
  /// category switch), so we still remember the intent and let
  /// attach()/registerItem() deliver focus once items arrive — but we
  /// report false so the caller knows focus did NOT land yet and can
  /// keep the sidebar selection instead of releasing it into the void
  /// (the bug on a genuinely empty / no-results category).
  bool focusFirst() {
    if (_streamIds.isEmpty) {
      _pendingFocusFirst = true;
      return false;
    }
    return focusIndex(0);
  }

  /// Focus the most recently focused poster if it still exists in the
  /// current list; otherwise the first item. The intended entry point
  /// when closing a detail view: caller doesn't need to remember which
  /// streamId was focused, the controller tracks it.
  bool focusCurrentOrFirst() {
    // Nothing loaded yet → defer, but report false (see [focusFirst]).
    if (_streamIds.isEmpty) {
      _pendingFocusFirst = true;
      return false;
    }
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
    // viewport). Also arm the deferred path so a slower mount (weak TV)
    // is still caught by registerItem().
    _pendingFocusStreamId = streamId;
    _scrollToIndex(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocus(streamId, attemptsLeft: 2);
    });
    return true;
  }

  void _retryFocus(int streamId, {required int attemptsLeft}) {
    final node = _nodes[streamId];
    if (node != null && node.canRequestFocus) {
      if (_pendingFocusStreamId == streamId) _pendingFocusStreamId = -1;
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
