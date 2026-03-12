import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    // Watch channels from all types that have playback progress (continue watching)
    final moviesAsync = ref.watch(_recentlyWatchedProvider('movie'));
    final seriesAsync = ref.watch(_recentlyWatchedProvider('series'));

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  Icon(Icons.bookmark_outlined, color: AppColors.primary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    l10n.favoritesHistory,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: isDark ? AppColors.textDark : AppColors.textLight),
                  ),
                ],
              ),
            ),

            // Continue Watching Movies
            _SectionHeader(title: l10n.continueWatchingMovies, icon: Icons.movie_outlined),
            const SizedBox(height: 10),
            moviesAsync.when(
              data: (channels) => channels.isEmpty
                  ? _EmptyState(message: l10n.noWatchedMovies)
                  : _HorizontalList(channels: channels, onPlay: (ch) => _play(context, ref, ch, 'movie')),
              loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 28),

            // Continue Watching Series
            _SectionHeader(title: l10n.continueWatchingSeries, icon: Icons.tv_outlined),
            const SizedBox(height: 10),
            seriesAsync.when(
              data: (channels) => channels.isEmpty
                  ? _EmptyState(message: l10n.noWatchedSeries)
                  : _HorizontalList(channels: channels, onPlay: (ch) => _play(context, ref, ch, 'series')),
              loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  void _play(BuildContext context, WidgetRef ref, Channel channel, String type) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    final prefix = type == 'movie' ? 'movie' : 'series';
    final url = '${account.url}/$prefix/${account.username}/${account.password}/${channel.streamId}.mkv';
    context.push('/player', extra: {
      'url': url,
      'title': channel.name,
      'type': type == 'movie' ? VideoType.movie : VideoType.series,
      'logo': channel.streamIcon,
      'plot': channel.plot,
      'genre': channel.genre,
      'year': channel.year,
      'director': channel.director,
      'cast': channel.cast,
      'rating': channel.rating,
    });
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondaryDark, size: 18),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? AppColors.textDark : AppColors.textLight)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Center(
        child: Text(message, style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 14)),
      ),
    );
  }
}

class _HorizontalList extends StatelessWidget {
  final List<Channel> channels;
  final Function(Channel) onPlay;
  const _HorizontalList({required this.channels, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: channels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) => _FavCard(channel: channels[index], onTap: () => onPlay(channels[index])),
        ),
      ),
    );
  }
}

class _FavCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  const _FavCard({required this.channel, required this.onTap});
  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        setState(() => _isFocused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 200));
            }
          });
        }
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _isFocused ? AppColors.primary : Colors.transparent, width: _isFocused ? 2 : 0),
            boxShadow: _isFocused ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12)] : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.channel.streamIcon != null
                    ? Image.network(widget.channel.streamIcon!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                    : _placeholder(),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                // Play icon overlay
                Center(
                  child: AnimatedScale(
                    scale: _isFocused ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 6,
                  right: 6,
                  child: Text(
                    widget.channel.name,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceElevatedDark,
      child: Center(child: Icon(Icons.movie_outlined, color: AppColors.textTertiaryDark, size: 32)),
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final _recentlyWatchedProvider = StreamProvider.family<List<Channel>, String>((ref, type) {
  return ref.watch(contentRepositoryProvider).watchRecentChannels(type, limit: 20);
});
