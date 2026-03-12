import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';
import 'package:lifeostv/utils/platform_utils.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  final FocusNode _gridFocus = FocusNode();
  Timer? _debounce;
  int _searchRequestId = 0;
  List<Channel> _movieResults = [];
  List<Channel> _seriesResults = [];
  List<Channel> _liveResults = [];
  bool _isSearching = false;

  bool get _hasResults => _movieResults.isNotEmpty || _seriesResults.isNotEmpty || _liveResults.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _textFocus.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final requestId = ++_searchRequestId;
    if (query.trim().isEmpty) {
      setState(() {
        _movieResults = [];
        _seriesResults = [];
        _liveResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final repo = ref.read(contentRepositoryProvider);
      final trimmed = query.trim();
      // Search all types in parallel for lower latency on big datasets.
      final results = await Future.wait([
        repo.searchChannelsByType(trimmed, 'movie', limit: 60),
        repo.searchChannelsByType(trimmed, 'series', limit: 60),
        repo.searchChannelsByType(trimmed, 'live', limit: 60),
      ]);
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _movieResults = results[0];
          _seriesResults = results[1];
          _liveResults = results[2];
          _isSearching = false;
        });
      }
    });
  }

  void _onResultTap(Channel channel) {
    if (channel.type == 'live') {
      _playLive(channel);
    } else {
      // Set pending detail so the target screen opens the detail panel
      ref.read(pendingDetailChannelProvider.notifier).set(channel);

      // Navigate to the correct branch — this pops search and switches tab
      if (channel.type == 'movie') {
        context.go('/movies');
      } else if (channel.type == 'series') {
        context.go('/series');
      }
    }
  }

  Widget _buildSectionHeader(IconData icon, String title, Color color, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildResultGrid(List<Channel> channels) {
    final isMobile = isMobilePlatform;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? 140 : 180,
        childAspectRatio: isMobile ? 0.60 : 0.65,
        crossAxisSpacing: isMobile ? 8 : 12,
        mainAxisSpacing: isMobile ? 8 : 12,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final ch = channels[index];
        return _SearchResultCard(
          channel: ch,
          onTap: () => _onResultTap(ch),
        );
      },
    );
  }

  void _playLive(Channel channel) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    final quality = ref.read(settingsProvider).streamQuality;
    final url = (account.type == 'm3u' && channel.streamUrl != null && channel.streamUrl!.isNotEmpty)
        ? channel.streamUrl!
        : StreamUrlBuilder.live(account.url, account.username ?? '', account.password ?? '', channel.streamId, quality: quality);
    context.push('/player', extra: {
      'url': url,
      'title': channel.name,
      'type': VideoType.live,
      'logo': channel.streamIcon,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = isMobilePlatform;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Column(
            children: [
              // Search bar
              Container(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 12 : 20,
                  isMobile ? 10 : 16,
                  isMobile ? 12 : 20,
                  isMobile ? 8 : 12,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.backgroundDark,
                  border: Border(bottom: BorderSide(color: AppColors.borderDark)),
                ),
                child: Row(
                  children: [
                    // Back button — bigger touch target on mobile
                    _FocusableIconButton(
                      icon: Icons.arrow_back,
                      size: isMobile ? 44 : 36,
                      iconSize: isMobile ? 24 : 20,
                      onTap: _goBack,
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    // Search input
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _textFocus,
                        autofocus: true,
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) {
                          // Move focus to results grid
                          if (_hasResults) {
                            _gridFocus.requestFocus();
                          }
                        },
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: isMobile ? 16 : 15,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.search,
                          hintStyle: const TextStyle(color: AppColors.textTertiaryDark),
                          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiaryDark, size: 20),
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: AppColors.textTertiaryDark, size: 18),
                                  onPressed: () {
                                    _controller.clear();
                                    _onSearchChanged('');
                                    _textFocus.requestFocus();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: isMobile ? 14 : 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Results — grouped by type
              Expanded(
                child: _isSearching
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : !_hasResults
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _controller.text.isEmpty ? Icons.search : Icons.search_off,
                                  size: 48,
                                  color: AppColors.textDisabledDark,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _controller.text.isEmpty
                                      ? l10n.search
                                      : l10n.noChannels,
                                  style: const TextStyle(
                                    color: AppColors.textTertiaryDark,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Focus(
                            focusNode: _gridFocus,
                            skipTraversal: true,
                            child: ListView(
                              padding: EdgeInsets.all(isMobile ? 12 : 20),
                              children: [
                                // Movies section
                                if (_movieResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.movie_outlined, l10n.movie, AppColors.primary, _movieResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_movieResults),
                                  const SizedBox(height: 24),
                                ],
                                // Series section
                                if (_seriesResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.tv_outlined, l10n.seriesLabel, AppColors.accent, _seriesResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_seriesResults),
                                  const SizedBox(height: 24),
                                ],
                                // Live TV section
                                if (_liveResults.isNotEmpty) ...[
                                  _buildSectionHeader(Icons.live_tv_outlined, l10n.liveTV, Colors.red, _liveResults.length),
                                  const SizedBox(height: 10),
                                  _buildResultGrid(_liveResults),
                                ],
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Result Card
// =============================================================================

class _SearchResultCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _SearchResultCard({required this.channel, required this.onTap});

  @override
  State<_SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<_SearchResultCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isActive = _isFocused || _isHovered;
    final l10n = AppLocalizations.of(context)!;

    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isFocused ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(10),
                border: _isFocused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : isActive
                        ? Border.all(color: AppColors.borderDark, width: 1)
                        : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Poster
                  Expanded(
                    child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
                        ? Image.network(
                            ch.streamIcon!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholderIcon(),
                          )
                        : _placeholderIcon(),
                  ),
                  // Info
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ch.name,
                          style: TextStyle(
                            color: isActive ? AppColors.textDark : AppColors.textSecondaryDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: _typeColor(ch.type).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _typeLabel(ch.type, l10n),
                            style: TextStyle(
                              color: _typeColor(ch.type),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: AppColors.surfaceElevatedDark,
      child: Center(
        child: Icon(Icons.tv, color: AppColors.textDisabledDark, size: 32),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'live':
        return Colors.red;
      case 'movie':
        return AppColors.primary;
      case 'series':
        return AppColors.accent;
      default:
        return AppColors.textTertiaryDark;
    }
  }

  String _typeLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'live':
        return l10n.live;
      case 'movie':
        return l10n.movie;
      case 'series':
        return l10n.seriesLabel;
      default:
        return type.toUpperCase();
    }
  }
}

// =============================================================================
// Focusable Icon Button
// =============================================================================

class _FocusableIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _FocusableIconButton({
    required this.icon,
    required this.onTap,
    this.size = 36,
    this.iconSize = 20,
  });

  @override
  State<_FocusableIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<_FocusableIconButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _isFocused ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
          ),
          child: Icon(
            widget.icon,
            color: _isFocused ? AppColors.primary : AppColors.textSecondaryDark,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}
