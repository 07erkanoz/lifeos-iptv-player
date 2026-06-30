import 'package:flutter/widgets.dart';

/// Imperative focus controller for a vertical, single-column list of
/// addressable items — Live TV's channel list is the prototype caller.
///
/// Mirrors [TvPosterGridController] in shape but specialized:
/// - one column → no row/col arithmetic
/// - row height is uniform → scroll-to-index math is a single
///   multiplication
/// - back/forward edge callbacks live on the widget (left/right) since
///   a channel-list cell only has up/down internally
///
/// The lazy-mount safety story is identical: only items currently in
/// the viewport mount FocusNodes, so jumping to an off-screen channel
/// requires scroll-then-retry. Two retry attempts cover the common
/// case where ListView builds in two passes.
class TvIndexedListController {
  /// channelId → FocusNode for items currently mounted. Items outside
  /// the viewport / cache extent are absent.
  final Map<int, FocusNode> _nodes = {};

  /// Ordered list of channelIds the list is rendering. Index in this
  /// list is what `focusIndex` / D-pad up-down arithmetic walk.
  List<int> _channelIds = const [];

  /// The list's ScrollController. Null while detached.
  ScrollController? _scrollController;

  /// Uniform row height in logical pixels — set by the widget from a
  /// LayoutBuilder pass. Used to compute the approximate scroll offset
  /// for an off-screen target.
  double _itemHeight = 0;

  /// Top padding the widget applied; folded into scroll offset math.
  double _paddingTop = 0;

  /// channelId of the most recently focused cell. Used by callers to
  /// restore focus after navigation away (e.g. back from a player).
  int _lastFocusedChannelId = -1;

  /// Deferred-focus intent. On a slow TV, switching category (or first
  /// open) rebuilds the list with async data + FocusNodes landing several
  /// frames after the 2-frame retry window. Rather than dropping focus
  /// into the void, we remember the intent here and fulfil it from
  /// [attach] (when the channelIds arrive) or [registerItem] (when the
  /// target row finally mounts). Mirrors TvPosterGridController.
  bool _pendingFocusFirst = false;
  int _pendingFocusChannelId = -1;

  // ── Lifecycle: widget ↔ controller ──────────────────────────────────

  void attach({
    required ScrollController scrollController,
    required double itemHeight,
    required double paddingTop,
    required List<int> channelIds,
  }) {
    _scrollController = scrollController;
    _itemHeight = itemHeight;
    _paddingTop = paddingTop;
    _channelIds = channelIds;
    // The data a deferred focus was waiting on may have just arrived.
    if ((_pendingFocusFirst || _pendingFocusChannelId >= 0) &&
        channelIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingFocusChannelId >= 0 &&
            _channelIds.contains(_pendingFocusChannelId)) {
          final id = _pendingFocusChannelId;
          _pendingFocusChannelId = -1;
          _pendingFocusFirst = false;
          focusByChannelId(id);
        } else if (_pendingFocusFirst) {
          _pendingFocusFirst = false;
          _pendingFocusChannelId = -1;
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

  void registerItem(int channelId, FocusNode node) {
    _nodes[channelId] = node;
    // Fulfil a deferred focus the moment its target row (or, for a
    // first-item request, the first channel) actually mounts.
    if (!node.canRequestFocus) return;
    if (_pendingFocusChannelId == channelId) {
      _pendingFocusChannelId = -1;
      _pendingFocusFirst = false;
      node.requestFocus();
    } else if (_pendingFocusFirst &&
        _channelIds.isNotEmpty &&
        channelId == _channelIds.first) {
      _pendingFocusFirst = false;
      node.requestFocus();
    }
  }

  void unregisterItem(int channelId, FocusNode node) {
    if (identical(_nodes[channelId], node)) {
      _nodes.remove(channelId);
    }
  }

  /// Called by an item when it gains focus.
  void notifyFocused(int channelId) {
    _lastFocusedChannelId = channelId;
  }

  // ── Read-only state ─────────────────────────────────────────────────

  int get lastFocusedChannelId => _lastFocusedChannelId;
  int get itemCount => _channelIds.length;
  List<int> get channelIds => List.unmodifiable(_channelIds);
  bool get hasScrollController => _scrollController != null;

  // ── Focus API ───────────────────────────────────────────────────────

  /// Focus the first row. On an empty list (data not loaded yet) the
  /// intent is remembered and fulfilled from [attach]/[registerItem]
  /// once rows arrive; returns false so the caller knows focus hasn't
  /// landed yet (and can keep the sidebar selection rather than
  /// releasing focus into the void).
  bool focusFirst() {
    if (_channelIds.isEmpty) {
      _pendingFocusFirst = true;
      return false;
    }
    return focusIndex(0);
  }

  bool focusByChannelId(int channelId) {
    final index = _channelIds.indexOf(channelId);
    if (index < 0) return false;
    return focusIndex(index);
  }

  bool focusCurrentOrFirst() {
    if (_channelIds.isEmpty) {
      _pendingFocusFirst = true;
      return false;
    }
    if (_lastFocusedChannelId >= 0 &&
        _channelIds.contains(_lastFocusedChannelId)) {
      return focusByChannelId(_lastFocusedChannelId);
    }
    return focusFirst();
  }

  bool focusIndex(int index) {
    if (index < 0 || index >= _channelIds.length) return false;
    final channelId = _channelIds[index];
    final mountedNode = _nodes[channelId];
    if (mountedNode != null && mountedNode.canRequestFocus) {
      mountedNode.requestFocus();
      return true;
    }
    // Item not mounted: approximate-scroll into view, then retry on
    // the next frame. Two extra attempts beyond the immediate try
    // cover ListView's two-pass build (initial layout, then a
    // viewport-aware repaint). Arm the deferred path too so a slower
    // mount (weak TV) is still caught by registerItem().
    _pendingFocusChannelId = channelId;
    _scrollToIndex(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocus(channelId, attemptsLeft: 2);
    });
    return true;
  }

  void _retryFocus(int channelId, {required int attemptsLeft}) {
    final node = _nodes[channelId];
    if (node != null && node.canRequestFocus) {
      if (_pendingFocusChannelId == channelId) _pendingFocusChannelId = -1;
      node.requestFocus();
      return;
    }
    if (attemptsLeft <= 0) {
      // Last resort: focus the first mounted node so focus never
      // lands nowhere.
      for (final id in _channelIds) {
        final n = _nodes[id];
        if (n != null && n.canRequestFocus) {
          n.requestFocus();
          return;
        }
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryFocus(channelId, attemptsLeft: attemptsLeft - 1);
    });
  }

  void _scrollToIndex(int index) {
    final scroll = _scrollController;
    if (scroll == null || !scroll.hasClients) return;
    if (_itemHeight <= 0) return;
    final viewport = scroll.position.viewportDimension;
    // Center the target row in viewport for TV ergonomics.
    final targetOffset =
        _paddingTop + index * _itemHeight - viewport / 2 + _itemHeight / 2;
    final clamped =
        targetOffset.clamp(0.0, scroll.position.maxScrollExtent).toDouble();
    scroll.jumpTo(clamped);
  }
}
