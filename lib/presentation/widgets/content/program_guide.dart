import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

class ProgramGuide extends ConsumerWidget {
  final Channel channel;

  const ProgramGuide({super.key, required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final programsAsync = ref.watch(programsProvider(channel.streamId));

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel Header
          Row(
            children: [
              if (channel.streamIcon != null)
                Image.network(
                  channel.streamIcon!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.tv, size: 80, color: Colors.white24),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    programsAsync.maybeWhen(
                      data: (programs) {
                        if (programs.isEmpty) return const SizedBox();
                        final current = programs.first;
                        return Text(
                          '${l10n.nowPlaying}: ${current.title}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        );
                      },
                      orElse: () => const SizedBox(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // EPG List
          Text(
            l10n.programGuide,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: programsAsync.when(
              data: (programs) {
                if (programs.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.noProgramInfo,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: programs.length,
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    final start = DateFormat('HH:mm').format(program.start);
                    final end = DateFormat('HH:mm').format(program.stop);

                    return ListTile(
                      title: Text(
                        program.title,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '$start - $end',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      leading:
                          const Icon(Icons.access_time, color: Colors.grey),
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  '${l10n.error}: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Action Buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _playChannel(context, ref),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.play),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _toggleFavorite(context, ref, l10n),
                icon: const Icon(Icons.favorite_border),
                label: Text(l10n.addToFavorites),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build a working stream URL using the active account + user's quality
  /// preference, then push the player route. M3U accounts use the channel's
  /// direct streamUrl when present.
  void _playChannel(BuildContext context, WidgetRef ref) {
    final account = ref.read(currentAccountProvider).value;
    if (account == null) return;
    final quality = ref.read(settingsProvider).streamQuality;

    final url = (account.type == 'm3u' &&
            channel.streamUrl != null &&
            channel.streamUrl!.isNotEmpty)
        ? channel.streamUrl!
        : StreamUrlBuilder.live(
            account.url,
            account.username ?? '',
            account.password ?? '',
            channel.streamId,
            quality: quality,
          );

    final programs = ref.read(programsProvider(channel.streamId)).value;
    final current = (programs != null && programs.isNotEmpty) ? programs.first : null;

    GoRouter.of(context).push('/player', extra: {
      'url': url,
      'title': channel.name,
      'logo': channel.streamIcon,
      'type': VideoType.live,
      'programTitle': current?.title,
      'programStart': current?.start,
      'programEnd': current?.stop,
    });
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final added = await ref.read(favoritesRepositoryProvider).toggleFavorite(
          channel.streamId,
          'live',
          channel.name,
          channel.streamIcon,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? l10n.addedToFavorites : l10n.removedFromFavorites),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

final programsProvider = StreamProvider.family<List<Program>, int>((ref, channelId) {
  return ref.watch(contentRepositoryProvider).watchPrograms(channelId);
});
