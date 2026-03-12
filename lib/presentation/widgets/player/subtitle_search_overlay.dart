import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/services/opensubtitles_service.dart';

/// OpenSubtitles search overlay for the video player.
/// Shows search results, allows downloading and loading subtitles.
class SubtitleSearchOverlay extends StatefulWidget {
  final String title;
  final String? year;
  final String preferredLanguage;
  final OpenSubtitlesService service;
  final void Function(String vttContent, String label) onSubtitleSelected;
  final VoidCallback onClose;

  const SubtitleSearchOverlay({
    super.key,
    required this.title,
    this.year,
    required this.preferredLanguage,
    required this.service,
    required this.onSubtitleSelected,
    required this.onClose,
  });

  @override
  State<SubtitleSearchOverlay> createState() => _SubtitleSearchOverlayState();
}

class _SubtitleSearchOverlayState extends State<SubtitleSearchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideAnim;
  late final Animation<Offset> _slideOffset;
  final _focusNode = FocusNode();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<ExternalSubtitle> _results = [];
  bool _isSearching = false;
  bool _isDownloading = false;
  String? _error;
  int? _downloadingId;

  @override
  void initState() {
    super.initState();
    _slideAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideOffset = Tween<Offset>(
      begin: const Offset(1, 0), // Slide from right
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideAnim, curve: Curves.easeOut));
    _slideAnim.forward();

    _searchController.text = widget.title;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _search();
    });
  }

  @override
  void dispose() {
    _slideAnim.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await widget.service.search(SubtitleSearchParams(
        query: query,
        languages: '${widget.preferredLanguage},en',
        year: widget.year != null ? int.tryParse(widget.year!) : null,
      ));

      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _download(ExternalSubtitle sub) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadingId = sub.fileId;
    });

    try {
      final result = await widget.service.download(sub.fileId);
      if (result != null && mounted) {
        final label = '${sub.languageLabel} - ${sub.release ?? sub.fileName ?? 'OpenSubtitles'}';
        widget.onSubtitleSelected(result.content, label);
        _close();
      } else if (mounted) {
        setState(() {
          _error = 'Download failed';
          _isDownloading = false;
          _downloadingId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isDownloading = false;
          _downloadingId = null;
        });
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth < 600 ? screenWidth * 0.85 : 420.0;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: _close,
        child: Container(
          color: Colors.black38,
          child: Row(
            children: [
              const Spacer(),
              // Panel slides from right
              SlideTransition(
                position: _slideOffset,
                child: GestureDetector(
                  onTap: () {}, // Prevent tap-through
                  child: ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(20),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        width: panelWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.8),
                              Colors.black.withValues(alpha: 0.92),
                            ],
                          ),
                          border: const Border(
                            left: BorderSide(color: Colors.white10, width: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildHeader(),
                            _buildSearchBar(),
                            const Divider(color: Colors.white10, height: 1),
                            Expanded(child: _buildResults()),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.subtitles, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'OpenSubtitles',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Film veya dizi adı...',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSearching ? null : _search,
            icon: _isSearching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.search, color: AppColors.primary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'Altyazı bulunamadı',
          style: TextStyle(color: Colors.white30, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _results.length,
      itemBuilder: (_, i) => _buildSubtitleTile(_results[i]),
    );
  }

  Widget _buildSubtitleTile(ExternalSubtitle sub) {
    final isDownloading = _downloadingId == sub.fileId;

    return InkWell(
      onTap: isDownloading ? null : () => _download(sub),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: Row(
          children: [
            // Language badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                sub.language.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub.release ?? sub.fileName ?? 'Subtitle',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Download count
                      Icon(Icons.download, color: Colors.white24, size: 11),
                      const SizedBox(width: 3),
                      Text(
                        '${sub.downloadCount}',
                        style: const TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                      // Trusted badge
                      if (sub.trusted) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'TRUSTED',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      // Hearing impaired badge
                      if (sub.hearingImpaired) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.hearing_disabled, color: Colors.white24, size: 11),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Download / loading indicator
            if (isDownloading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            else
              const Icon(Icons.download, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}
