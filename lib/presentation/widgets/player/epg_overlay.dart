import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';

/// EPG program guide overlay for live TV player.
/// Shows current + upcoming programs for the active channel.
class EpgOverlay extends StatefulWidget {
  final List<Program> programs;
  final String channelName;
  final String? channelLogo;
  final VoidCallback onClose;

  const EpgOverlay({
    super.key,
    required this.programs,
    required this.channelName,
    this.channelLogo,
    required this.onClose,
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

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(0, 1), // Slide from bottom
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideAnim, curve: Curves.easeOut));
    _slideAnim.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      // Scroll to the current program
      _scrollToCurrentProgram();
    });
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
    if (currentIdx > 0 && _scrollController.hasClients) {
      // Each item is ~72px height, scroll to center it
      final offset = (currentIdx * 72.0 - 72).clamp(0.0, double.maxFinite);
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    // Close on Escape, Back, or G key
    if (k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.goBack ||
        k == LogicalKeyboardKey.keyG) {
      _close();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _close() {
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
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
                            const Divider(
                              color: Colors.white10,
                              height: 1,
                            ),
                            // Program list
                            Expanded(
                              child: widget.programs.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Program bilgisi bulunamadı',
                                        style: TextStyle(
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
              child: Image.network(
                widget.channelLogo!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevatedDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.tv,
                    color: Colors.white24,
                    size: 18,
                  ),
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
                const Text(
                  'Program Rehberi',
                  style: TextStyle(
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

  Widget _buildProgramTile(Program program, DateTime now, bool isCompact) {
    final isCurrent =
        program.start.isBefore(now) && program.stop.isAfter(now);
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isCurrent
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
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
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
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w400,
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 5),
                        SizedBox(width: 3),
                        Text(
                          'CANLI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
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
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
