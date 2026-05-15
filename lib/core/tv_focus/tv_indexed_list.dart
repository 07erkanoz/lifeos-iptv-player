import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_indexed_list_controller.dart';

/// A `ListView.builder`-backed vertical list with deterministic D-pad
/// up/down navigation, lazy-mount-safe focus restore, and
/// scroll-on-focus. Designed for Live TV's channel list and any other
/// "tall list of focusable cells with neighbors on the left and right
/// of the list, not inside it" layout.
///
/// Edge navigation is delegated upward:
/// - [onLeftEdge] fires on D-pad left from any cell (the whole list is
///   the leftmost element relative to the cell — there's nothing
///   inside the row to step to).
/// - [onRightEdge] fires on D-pad right; typical Live TV use is "open
///   the EPG / focus the timeline for the highlighted channel".
/// - [onTopEdge] / [onBottomEdge] fire on D-pad up from row 0 and
///   down from the last row.
class TvIndexedList<T> extends StatefulWidget {
  final TvIndexedListController controller;
  final List<T> items;
  final int Function(T item) channelIdOf;
  final Widget Function(BuildContext context, T item, bool isFocused)
      itemBuilder;
  final void Function(T item) onActivate;

  /// Fixed height per row in logical pixels. The controller uses this
  /// to compute approximate scroll offsets for off-screen targets.
  final double itemExtent;

  final EdgeInsetsGeometry padding;

  final VoidCallback? onLeftEdge;
  final VoidCallback? onRightEdge;
  final VoidCallback? onTopEdge;
  final VoidCallback? onBottomEdge;

  /// Fired when an item gains focus. Mirrors TvPosterGrid's
  /// onFocusGained — used by callers to drive a preview / EPG sync.
  final void Function(T item)? onFocusGained;

  /// Optional external scroll controller. When provided, the widget
  /// uses it instead of creating its own — needed by callers (Live
  /// TV) that sync scrolling between this list and a sibling
  /// (the EPG timeline's vertical scroll). When null, an internal
  /// controller is created and disposed with the widget.
  final ScrollController? scrollController;

  const TvIndexedList({
    super.key,
    required this.controller,
    required this.items,
    required this.channelIdOf,
    required this.itemBuilder,
    required this.onActivate,
    required this.itemExtent,
    this.padding = EdgeInsets.zero,
    this.onLeftEdge,
    this.onRightEdge,
    this.onTopEdge,
    this.onBottomEdge,
    this.onFocusGained,
    this.scrollController,
  });

  @override
  State<TvIndexedList<T>> createState() => _TvIndexedListState<T>();
}

class _TvIndexedListState<T> extends State<TvIndexedList<T>> {
  ScrollController? _ownedScrollController;
  ScrollController get _activeScrollController =>
      widget.scrollController ?? _ownedScrollController!;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null) {
      _ownedScrollController = ScrollController();
    }
  }

  @override
  void dispose() {
    widget.controller.detach(_activeScrollController);
    _ownedScrollController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paddingResolved =
        widget.padding.resolve(Directionality.of(context));
    final channelIds =
        widget.items.map(widget.channelIdOf).toList(growable: false);
    widget.controller.attach(
      scrollController: _activeScrollController,
      itemHeight: widget.itemExtent,
      paddingTop: paddingResolved.top,
      channelIds: channelIds,
    );

    return ListView.builder(
      controller: _activeScrollController,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final channelId = widget.channelIdOf(item);
        return _TvIndexedListItem<T>(
          key: ValueKey('tvchan-$channelId'),
          channelId: channelId,
          index: index,
          total: widget.items.length,
          controller: widget.controller,
          builder: (ctx, focused) => widget.itemBuilder(ctx, item, focused),
          onActivate: () => widget.onActivate(item),
          onLeftEdge: widget.onLeftEdge,
          onRightEdge: widget.onRightEdge,
          onTopEdge: widget.onTopEdge,
          onBottomEdge: widget.onBottomEdge,
          onFocusGained: widget.onFocusGained == null
              ? null
              : () => widget.onFocusGained!(item),
        );
      },
    );
  }
}

class _TvIndexedListItem<T> extends StatefulWidget {
  final int channelId;
  final int index;
  final int total;
  final TvIndexedListController controller;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final VoidCallback onActivate;
  final VoidCallback? onLeftEdge;
  final VoidCallback? onRightEdge;
  final VoidCallback? onTopEdge;
  final VoidCallback? onBottomEdge;
  final VoidCallback? onFocusGained;

  const _TvIndexedListItem({
    super.key,
    required this.channelId,
    required this.index,
    required this.total,
    required this.controller,
    required this.builder,
    required this.onActivate,
    this.onLeftEdge,
    this.onRightEdge,
    this.onTopEdge,
    this.onBottomEdge,
    this.onFocusGained,
  });

  @override
  State<_TvIndexedListItem<T>> createState() => _TvIndexedListItemState<T>();
}

class _TvIndexedListItemState<T> extends State<_TvIndexedListItem<T>> {
  late final FocusNode _node;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(debugLabel: 'TvChannel_${widget.channelId}');
    widget.controller.registerItem(widget.channelId, _node);
  }

  @override
  void dispose() {
    widget.controller.unregisterItem(widget.channelId, _node);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused) {
      widget.controller.notifyFocused(widget.channelId);
      widget.onFocusGained?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _node.context;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
    if (mounted) setState(() => _focused = focused);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final idx = widget.index;
    final total = widget.total;

    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (idx == 0) {
        widget.onTopEdge?.call();
        return KeyEventResult.handled;
      }
      widget.controller.focusIndex(idx - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (idx >= total - 1) {
        widget.onBottomEdge?.call();
        return KeyEventResult.handled;
      }
      widget.controller.focusIndex(idx + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onLeftEdge?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onRightEdge?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKey,
      child: widget.builder(context, _focused),
    );
  }
}
