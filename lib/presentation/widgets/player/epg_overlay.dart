import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/core/perf/frosted.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// EPG program guide overlay for live TV player.
/// Shows current + upcoming programs for the active channel.
class EpgOverlay extends StatefulWidget {
  final List<Program> programs;
  final String channelName;
  final String? channelLogo;
  final VoidCallback onClose;

  /// Catch-up / timeshift handler. When non-null and a program is in
  /// the past but within the provider's timeshift window, the past
  /// programme tiles render as tappable replay buttons. The handler
  /// receives the [Program] and is expected to open a new player
  /// session pointed at the Xtream timeshift URL (built via
  /// `StreamUrlBuilder.timeshift`). Null disables the affordance.
  final Future<void> Function(Program program)? onCatchUp;

  /// How far back the Xtream timeshift buffer reaches. Programmes
  /// whose `stop` is older than this are non-clickable (the server
  /// would 404). Defaults to 5 days, the rough median across
  /// providers; passing 0 effectively disables the affordance.
  final Duration catchUpWindow;

  const EpgOverlay({
    super.key,
    required this.programs,
    required this.channelName,
    this.channelLogo,
    required this.onClose,
    this.onCatchUp,
    this.catchUpWindow = const Duration(days: 5),
  });

  @override
  State<EpgOverlay> createState() => _EpgOverlayState();
}

class _EpgOverlayState extends State<EpgOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideAnim;
  late final Animation<Offset> _slideOffset;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  /// D-pad highlighted program row. Drives keyboard/remote navigation of
  /// the list (the rows are index-simulated, not individual focus nodes).
  /// Seeded to the current programme on open.
  int _focusedIndex = -1;
  bool _closing = false;
  static const _kTileExtent = 72.0;

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      // Instant on TV — no slide composite over the live video surface.
      duration: PlatformHelper.anim(const Duration(milliseconds: 250)),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(0, 1), // Slide from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideAnim, curve: Curves.easeOut));
    _slideAnim.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      // Scroll to the current program
      _scrollToCurrentProgram();
    });
  }

  @override
  void didUpdateWidget(EpgOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId =
        _focusedIndex >= 0 && _focusedIndex < oldWidget.programs.length
        ? oldWidget.programs[_focusedIndex].id
        : null;
    final retained = widget.programs.indexWhere((p) => p.id == oldId);
    _focusedIndex = retained >= 0
        ? retained
        : (widget.programs.isEmpty ? -1 : 0);
  }

  @override
  void dispose() {
    _slideAnim.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentProgram() {
    final now = DateTime.now();
    int currentIdx = -1;
    for (var i = 0; i < widget.programs.length; i++) {
      final p = widget.programs[i];
      if (p.start.isBefore(now) && p.stop.isAfter(now)) {
        currentIdx = i;
        break;
      }
    }
    // Seed the D-pad highlight on the current programme (or the first row
    // if "now" isn't in the EPG window) so the remote has somewhere to go.
    if (widget.programs.isNotEmpty) {
      setState(() => _focusedIndex = currentIdx >= 0 ? currentIdx : 0);
    }
    if (currentIdx > 0 && _scrollController.hasClients) {
      // Each item is ~72px height, scroll to center it
      final offset = (currentIdx * _kTileExtent - _kTileExtent).clamp(
        0.0,
        double.maxFinite,
      );
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Bring the D-pad highlighted row into view as the user navigates.
  void _scrollToIndex(int idx) {
    if (!_scrollController.hasClients) return;
    final target = idx * _kTileExtent - _kTileExtent;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (event is KeyRepeatEvent &&
        k != LogicalKeyboardKey.arrowDown &&
        k != LogicalKeyboardKey.arrowUp)
      return KeyEventResult.handled;

    // Close on Escape, Back, or G key
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.browserBack ||
        k == LogicalKeyboardKey.keyG) {
      _close();
      return KeyEventResult.handled;
    }

    final count = widget.programs.length;
    if (count == 0) return KeyEventResult.handled;

    // D-pad navigation of the program list (rows are index-simulated).
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < count - 1) {
        setState(() => _focusedIndex++);
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }
    // Enter/OK → start catch-up replay for the highlighted programme when
    // it's in the timeshift window; no-op for live/future rows.
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
      if (_focusedIndex >= 0 && _focusedIndex < count) {
        _activateProgram(widget.programs[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }

    // Swallow remaining keys so they can't leak to the player behind us.
    return KeyEventResult.handled;
  }

  /// True when [program] is in the past and inside the catch-up window.
  bool _isCatchUpAble(Program program, DateTime now) =>
      program.stop.isBefore(now) &&
      widget.onCatchUp != null &&
      now.difference(program.stop) <= widget.catchUpWindow;

  void _activateProgram(Program program) {
    if (_isCatchUpAble(program, DateTime.now())) {
      widget.onCatchUp!.call(program);
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _slideAnim.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 600;
    final overlayHeight = isCompact ? screenHeight * 0.6 : screenHeight * 0.5;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: _close,
        child: Container(
          color: Colors.black38,
          child: Column(
            children: [
              // Tap-to-close area
              const Spacer(),
              // EPG panel slides from bottom
              SlideTransition(
                position: _slideOffset,
                child: GestureDetector(
                  onTap: () {}, // Prevent tap-through
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: Frosted(
                      sigma: 24,
                      child: Container(
                        height: overlayHeight,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.black.withValues(alpha: 0.9),
                            ],
                          ),
                          border: const Border(
                            top: BorderSide(color: Colors.white10, width: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Header
                            _buildHeader(context),
                            const Divider(color: Colors.white10, height: 1),
                            // Program list
                            Expanded(
                              child: widget.programs.isEmpty
                                  ? Center(
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.noProgramInfo,
                                        style: const TextStyle(
                                          color: Colors.white30,
                                          fontSize: 14,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      itemCount: widget.programs.length,
                                      itemBuilder: (_, i) => _buildProgramTile(
                                        widget.programs[i],
                                        now,
                                        isCompact,
                                        i == _focusedIndex,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(
        children: [
          // Channel logo
          if (widget.channelLogo != null && widget.channelLogo!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: widget.channelLogo!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                memCacheWidth: 108,
                errorWidget: (_, _, _) => Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevatedDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tv, color: Colors.white24, size: 18),
                ),
              ),
            ),
          if (widget.channelLogo != null && widget.channelLogo!.isNotEmpty)
            const SizedBox(width: 12),
          // Channel name + "Program Rehberi"
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.channelName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  AppLocalizations.of(context)!.programGuide,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Close button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildProgramTile(
    Program program,
    DateTime now,
    bool isCompact,
    bool isFocused,
  ) {
    final isCurrent = program.start.isBefore(now) && program.stop.isAfter(now);
    final isPast = program.stop.isBefore(now);
    final startStr = DateFormat('HH:mm').format(program.start);
    final stopStr = DateFormat('HH:mm').format(program.stop);
    final duration = program.stop.difference(program.start).inMinutes;

    // Current program progress
    double progress = 0;
    if (isCurrent) {
      final total = program.stop.difference(program.start).inSeconds;
      final elapsed = now.difference(program.start).inSeconds;
      if (total > 0) progress = (elapsed / total).clamp(0.0, 1.0);
    }

    // Catch-up gate: past + within timeshift window + caller supplied
    // a handler. Tiles outside the window stay non-tappable (the
    // server would 404 anyway).
    final isCatchUpAble =
        isPast &&
        widget.onCatchUp != null &&
        now.difference(program.stop) <= widget.catchUpWindow;

    final tile = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: isFocused
            ? AppColors.primary.withValues(alpha: 0.22)
            : isCurrent
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        // D-pad focus ring takes precedence over the "now playing" hint
        // so the remote user can always see where they are.
        border: isFocused
            ? Border.all(color: AppColors.primary, width: 2.5)
            : isCurrent
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Time range
                SizedBox(
                  width: 100,
                  child: Text(
                    '$startStr - $stopStr',
                    style: TextStyle(
                      color: isCurrent
                          ? AppColors.primary
                          : isPast
                          ? Colors.white24
                          : Colors.white54,
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                // Title
                Expanded(
                  child: Text(
                    program.title,
                    style: TextStyle(
                      color: isPast ? Colors.white30 : Colors.white,
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Duration badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${duration}dk',
                    style: TextStyle(
                      color: isPast ? Colors.white24 : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // LIVE badge for current program
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: Colors.white, size: 5),
                        const SizedBox(width: 3),
                        Text(
                          AppLocalizations.of(context)!.live,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
                // Catch-up replay icon — surfaces on past programmes
                // when the caller wired the timeshift handler. Tap
                // the whole row to start replay; this icon is just
                // the visual affordance.
                else if (isCatchUpAble) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.replay_circle_filled,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ],
              ],
            ),
            // Description (if available and current)
            if (isCurrent &&
                program.description != null &&
                program.description!.isNotEmpty &&
                !isCompact) ...[
              const SizedBox(height: 6),
              Text(
                program.description!,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Progress bar for current program
            if (isCurrent) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    // Wrap tappable catch-up tiles in InkWell so they read as
    // interactive. Non-catch-up tiles stay non-clickable to avoid
    // looking like dead buttons.
    if (!isCatchUpAble) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          // Fire-and-forget; the player route push handles its own
          // navigation animation. We deliberately don't `await` here
          // to avoid blocking the EPG overlay's gesture pipeline.
          widget.onCatchUp!.call(program);
        },
        child: tile,
      ),
    );
  }
}
