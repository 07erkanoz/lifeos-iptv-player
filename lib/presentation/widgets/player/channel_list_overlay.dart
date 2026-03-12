import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';

/// Channel list overlay for live TV player.
/// Slides in from the right, supports search, category filtering,
/// and keyboard/D-pad/touch navigation.
class ChannelListOverlay extends StatefulWidget {
  final List<PlayerChannel> channels;
  final int currentChannelIndex;
  final Map<String, String>? categoryNames;
  final ValueChanged<int> onChannelSelected;
  final VoidCallback onClose;

  const ChannelListOverlay({
    super.key,
    required this.channels,
    required this.currentChannelIndex,
    this.categoryNames,
    required this.onChannelSelected,
    required this.onClose,
  });

  @override
  State<ChannelListOverlay> createState() => _ChannelListOverlayState();
}

class _ChannelListOverlayState extends State<ChannelListOverlay>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();
  late AnimationController _slideAnim;
  late Animation<Offset> _slideOffset;

  String? _selectedCategoryId; // null = All
  String _searchQuery = '';
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideAnim, curve: Curves.easeOut));
    _slideAnim.forward();

    // Set initial focus to current channel
    _focusedIndex = widget.currentChannelIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
  }

  @override
  void dispose() {
    _slideAnim.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<PlayerChannel> get _filteredChannels {
    var list = widget.channels;
    if (_selectedCategoryId != null) {
      list = list.where((ch) => ch.categoryId == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((ch) => ch.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  List<MapEntry<String, String>> get _categories {
    final seen = <String>{};
    final cats = <MapEntry<String, String>>[];
    for (final ch in widget.channels) {
      final id = ch.categoryId;
      if (id != null && seen.add(id)) {
        final name = widget.categoryNames?[id] ?? id;
        cats.add(MapEntry(id, name));
      }
    }
    return cats;
  }

  void _scrollToFocused() {
    if (!_scrollController.hasClients) return;
    final filtered = _filteredChannels;
    if (_focusedIndex < 0 || _focusedIndex >= widget.channels.length) return;

    // Find index of current channel in filtered list
    final currentCh = widget.channels[_focusedIndex];
    final filteredIdx = filtered.indexWhere((ch) => ch.streamId == currentCh.streamId);
    if (filteredIdx < 0) return;

    final targetOffset = filteredIdx * 56.0; // approximate item height
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _selectCategory(String? id) {
    setState(() {
      _selectedCategoryId = id;
      _focusedIndex = widget.currentChannelIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _close() async {
    await _slideAnim.reverse();
    widget.onClose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      _close();
      return KeyEventResult.handled;
    }

    // Don't capture arrows when search field is focused
    if (_searchFocusNode.hasFocus) return KeyEventResult.ignored;

    final filtered = _filteredChannels;

    if (k == LogicalKeyboardKey.arrowDown) {
      final currentInFiltered = _focusedIndex >= 0 && _focusedIndex < widget.channels.length
          ? filtered.indexWhere((ch) => ch.streamId == widget.channels[_focusedIndex].streamId)
          : -1;
      final nextIdx = currentInFiltered + 1;
      if (nextIdx < filtered.length) {
        final globalIdx = widget.channels.indexWhere((ch) => ch.streamId == filtered[nextIdx].streamId);
        setState(() => _focusedIndex = globalIdx);
        _scrollToItem(nextIdx);
      }
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowUp) {
      final currentInFiltered = _focusedIndex >= 0 && _focusedIndex < widget.channels.length
          ? filtered.indexWhere((ch) => ch.streamId == widget.channels[_focusedIndex].streamId)
          : 0;
      final prevIdx = currentInFiltered - 1;
      if (prevIdx >= 0) {
        final globalIdx = widget.channels.indexWhere((ch) => ch.streamId == filtered[prevIdx].streamId);
        setState(() => _focusedIndex = globalIdx);
        _scrollToItem(prevIdx);
      }
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowLeft) {
      // Previous category
      final cats = _categories;
      if (cats.isEmpty) return KeyEventResult.handled;
      if (_selectedCategoryId == null) {
        _selectCategory(cats.last.key);
      } else {
        final idx = cats.indexWhere((c) => c.key == _selectedCategoryId);
        if (idx <= 0) {
          _selectCategory(null);
        } else {
          _selectCategory(cats[idx - 1].key);
        }
      }
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowRight) {
      // Next category
      final cats = _categories;
      if (cats.isEmpty) return KeyEventResult.handled;
      if (_selectedCategoryId == null) {
        _selectCategory(cats.first.key);
      } else {
        final idx = cats.indexWhere((c) => c.key == _selectedCategoryId);
        if (idx >= cats.length - 1) {
          _selectCategory(null);
        } else {
          _selectCategory(cats[idx + 1].key);
        }
      }
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.select) {
      if (_focusedIndex >= 0 && _focusedIndex < widget.channels.length) {
        widget.onChannelSelected(_focusedIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToItem(int filteredIndex) {
    if (!_scrollController.hasClients) return;
    final targetOffset = filteredIndex * 56.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth < 600 ? screenWidth * 0.85 : 400.0;
    final filtered = _filteredChannels;

    return SlideTransition(
      position: _slideOffset,
      child: Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xF2101012),
                border: const Border(
                  left: BorderSide(color: Colors.white10, width: 0.5),
                ),
              ),
              child: Focus(
                autofocus: true,
                onKeyEvent: _handleKey,
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.live_tv, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Kanal Listesi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                            onPressed: _close,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          ),
                        ],
                      ),
                    ),

                    // Search
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onSearch,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Kanal ara...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                          prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.35), size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear, color: Colors.white.withValues(alpha: 0.35), size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearch('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),

                    // Category tabs
                    if (_categories.isNotEmpty)
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          children: [
                            _CategoryTab(
                              label: 'Tümü',
                              isActive: _selectedCategoryId == null,
                              onTap: () => _selectCategory(null),
                            ),
                            ..._categories.map((cat) => _CategoryTab(
                              label: cat.value,
                              isActive: _selectedCategoryId == cat.key,
                              onTap: () => _selectCategory(cat.key),
                            )),
                          ],
                        ),
                      ),

                    const SizedBox(height: 4),

                    // Channel list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Kanal bulunamadı',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: filtered.length,
                              itemExtent: 56,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemBuilder: (context, index) {
                                final ch = filtered[index];
                                final globalIdx = widget.channels.indexWhere((c) => c.streamId == ch.streamId);
                                final isActive = globalIdx == widget.currentChannelIndex;
                                final isFocused = globalIdx == _focusedIndex;

                                return _ChannelItem(
                                  channel: ch,
                                  index: index + 1,
                                  isActive: isActive,
                                  isFocused: isFocused,
                                  onTap: () => widget.onChannelSelected(globalIdx),
                                  onHover: () => setState(() => _focusedIndex = globalIdx),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  Category Tab
// =============================================================================

class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isActive ? Colors.red.shade700 : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  Channel Item
// =============================================================================

class _ChannelItem extends StatefulWidget {
  final PlayerChannel channel;
  final int index;
  final bool isActive;
  final bool isFocused;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _ChannelItem({
    required this.channel,
    required this.index,
    required this.isActive,
    required this.isFocused,
    required this.onTap,
    required this.onHover,
  });

  @override
  State<_ChannelItem> createState() => _ChannelItemState();
}

class _ChannelItemState extends State<_ChannelItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isHighlight = widget.isActive || widget.isFocused || _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? Colors.red.withValues(alpha: 0.15)
                : isHighlight
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isFocused && !widget.isActive
                ? Border.all(color: Colors.white.withValues(alpha: 0.15))
                : widget.isActive && widget.isFocused
                    ? Border.all(color: Colors.red.withValues(alpha: 0.4))
                    : null,
          ),
          child: Row(
            children: [
              // Channel number
              SizedBox(
                width: 28,
                child: Text(
                  '${widget.index}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 10),

              // Logo
              if (widget.channel.logo != null && widget.channel.logo!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    widget.channel.logo!,
                    width: 32,
                    height: 22,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 22),
                  ),
                )
              else
                const SizedBox(width: 32, height: 22),
              const SizedBox(width: 10),

              // Name
              Expanded(
                child: Text(
                  widget.channel.name,
                  style: TextStyle(
                    color: widget.isActive ? Colors.white : Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Active indicator
              if (widget.isActive)
                const Text(
                  '\u25B6',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
