import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_poster_grid_controller.dart';

/// A `GridView.builder`-backed poster grid with deterministic D-pad
/// navigation, lazy-mount-safe focus restore, and scroll-on-focus so
/// the focused tile is always visible.
///
/// The widget is generic over the item type so callers keep their own
/// model (`Channel`, `_FavoriteEntry`, etc.) without an adapter.
/// Required hooks:
/// - [streamIdOf] turns an item into its stable identity for the
///   controller's focus map / lastFocusedStreamId tracking.
/// - [itemBuilder] renders the tile; receives `isFocused` so the tile
///   can drive its own focus ring / scale animation.
/// - [onActivate] fires on enter/select or tap.
///
/// Edge navigation is delegated upward:
/// - [onLeftEdge] fires when the user presses D-pad left on column 0
///   (typical use: open / focus the category sidebar).
/// - [onTopEdge] fires on D-pad up from row 0 (typical use: focus a
///   toolbar above the grid).
class TvPosterGrid<T> extends StatefulWidget {
  final TvPosterGridController controller;
  final List<T> items;
  final int Function(T item) streamIdOf;
  final Widget Function(BuildContext context, T item, bool isFocused)
      itemBuilder;
  final void Function(T item) onActivate;

  final int columns;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsetsGeometry padding;

  final VoidCallback? onLeftEdge;
  final VoidCallback? onTopEdge;

  /// Fired when an item gains focus (mouse hover or D-pad navigation).
  /// Lets screens drive a hero banner / preview from focus changes so
  /// the same state update happens regardless of input modality — the
  /// "hover" concept is replaced by focus on TV.
  final void Function(T item)? onFocusGained;

  /// Fired when the grid builds an item near the end of [items] — the
  /// cue for the screen to grow its page size (progressive loading), so
  /// a huge category is never materialised all at once.
  final VoidCallback? onNeedMore;

  const TvPosterGrid({
    super.key,
    required this.controller,
    required this.items,
    required this.streamIdOf,
    required this.itemBuilder,
    required this.onActivate,
    required this.columns,
    this.childAspectRatio = 0.66,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 12,
    this.padding = EdgeInsets.zero,
    this.onLeftEdge,
    this.onTopEdge,
    this.onFocusGained,
    this.onNeedMore,
  });

  @override
  State<TvPosterGrid<T>> createState() => _TvPosterGridState<T>();
}

class _TvPosterGridState<T> extends State<TvPosterGrid<T>> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    widget.controller.detach(_scrollController);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paddingResolved = widget.padding.resolve(Directionality.of(context));
        final colCount = widget.columns < 1 ? 1 : widget.columns;
        final horizontalPad = paddingResolved.left + paddingResolved.right;
        final crossExtent = (constraints.maxWidth - horizontalPad)
            .clamp(0, double.infinity)
            .toDouble();
        final totalGapWidth = widget.crossAxisSpacing * (colCount - 1);
        final tileWidth =
            ((crossExtent - totalGapWidth) / colCount).clamp(1.0, double.infinity);
        final tileHeight = tileWidth / widget.childAspectRatio;
        final rowStride = tileHeight + widget.mainAxisSpacing;

        final streamIds = widget.items.map(widget.streamIdOf).toList();
        widget.controller.attach(
          scrollController: _scrollController,
          columns: colCount,
          rowStride: rowStride,
          paddingTop: paddingResolved.top,
          streamIds: streamIds,
        );

        return GridView.builder(
          controller: _scrollController,
          padding: widget.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colCount,
            childAspectRatio: widget.childAspectRatio,
            crossAxisSpacing: widget.crossAxisSpacing,
            mainAxisSpacing: widget.mainAxisSpacing,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            // Progressive loading: when the grid reaches the last few
            // rows, ask the screen to grow the page. Deferred to after the
            // frame so we never mutate provider state mid-build.
            if (widget.onNeedMore != null &&
                index >= widget.items.length - colCount * 3) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onNeedMore!();
              });
            }
            final item = widget.items[index];
            final streamId = widget.streamIdOf(item);
            return _TvPosterItem<T>(
              key: ValueKey('tvposter-$streamId'),
              streamId: streamId,
              index: index,
              total: widget.items.length,
              columns: colCount,
              controller: widget.controller,
              builder: (ctx, focused) => widget.itemBuilder(ctx, item, focused),
              onActivate: () => widget.onActivate(item),
              onLeftEdge: widget.onLeftEdge,
              onTopEdge: widget.onTopEdge,
              onFocusGained: widget.onFocusGained == null
                  ? null
                  : () => widget.onFocusGained!(item),
            );
          },
        );
      },
    );
  }
}

class _TvPosterItem<T> extends StatefulWidget {
  final int streamId;
  final int index;
  final int total;
  final int columns;
  final TvPosterGridController controller;
  final Widget Function(BuildContext context, bool isFocused) builder;
  final VoidCallback onActivate;
  final VoidCallback? onLeftEdge;
  final VoidCallback? onTopEdge;
  final VoidCallback? onFocusGained;

  const _TvPosterItem({
    super.key,
    required this.streamId,
    required this.index,
    required this.total,
    required this.columns,
    required this.controller,
    required this.builder,
    required this.onActivate,
    this.onLeftEdge,
    this.onTopEdge,
    this.onFocusGained,
  });

  @override
  State<_TvPosterItem<T>> createState() => _TvPosterItemState<T>();
}

class _TvPosterItemState<T> extends State<_TvPosterItem<T>> {
  late final FocusNode _node;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node = FocusNode(debugLabel: 'TvPoster_${widget.streamId}');
    widget.controller.registerItem(widget.streamId, _node);
  }

  @override
  void dispose() {
    widget.controller.unregisterItem(widget.streamId, _node);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (focused) {
      widget.controller.notifyFocused(widget.streamId);
      widget.onFocusGained?.call();
      // Center the tile precisely after layout settles. The controller's
      // approximate jumpTo got us into the viewport; this aligns it for
      // a clean focus ring.
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

    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      widget.onActivate();
      return KeyEventResult.handled;
    }

    final cols = widget.columns;
    final idx = widget.index;
    final total = widget.total;
    final row = idx ~/ cols;
    final col = idx % cols;

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (col == 0) {
        widget.onLeftEdge?.call();
        return KeyEventResult.handled;
      }
      widget.controller.focusIndex(idx - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final next = idx + 1;
      // No wrap; stop at row end OR final item in last partial row.
      if (col == cols - 1 || next >= total) {
        return KeyEventResult.handled;
      }
      widget.controller.focusIndex(next);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (row == 0) {
        widget.onTopEdge?.call();
        return KeyEventResult.handled;
      }
      widget.controller.focusIndex(idx - cols);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final next = idx + cols;
      if (next >= total) {
        return KeyEventResult.handled; // bottom edge: no-op (no wrap)
      }
      widget.controller.focusIndex(next);
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
