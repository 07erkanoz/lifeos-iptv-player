import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';

class ProgramGuide extends ConsumerWidget {
  final Channel channel;

  const ProgramGuide({super.key, required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                Image.network(channel.streamIcon!, width: 80, height: 80, fit: BoxFit.contain, errorBuilder: (_,__,___)=>const Icon(Icons.tv, size: 80, color: Colors.white24)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(
                      channel.name,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    // Current Program info from list if available
                    programsAsync.maybeWhen(
                      data: (programs) {
                         if (programs.isEmpty) return const SizedBox();
                         final current = programs.first;
                         return Text(
                           'Now: ${current.title}',
                           style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 18),
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
          const Text('Yayın Akışı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(height: 16),
          
          Expanded(
            child: programsAsync.when(
              data: (programs) {
                if (programs.isEmpty) {
                   return const Center(child: Text('Yayın akışı bilgisi bulunamadı', style: TextStyle(color: Colors.white54)));
                }
                return ListView.builder(
                  itemCount: programs.length,
                  itemBuilder: (context, index) {
                    final program = programs[index];
                    final start = DateFormat('HH:mm').format(program.start);
                    final end = DateFormat('HH:mm').format(program.stop);
                    
                    return ListTile(
                      title: Text(program.title, style: const TextStyle(color: Colors.white)),
                      subtitle: Text('$start - $end', style: const TextStyle(color: Colors.grey)),
                      leading: const Icon(Icons.access_time, color: Colors.grey),
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Hata: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
          
          const Spacer(),
          
          // Action Buttons
          Row(
            children: [
              programsAsync.maybeWhen(
                data: (programs) {
                   final current = programs.isNotEmpty ? programs.first : null;
                   return ElevatedButton.icon(
                    onPressed: () {
                      if (context.mounted) {
                        GoRouter.of(context).push('/player', extra: {
                           'url': '', // TODO: Construct URL from account credentials + channel.streamId
                           'title': channel.name,
                           'logo': channel.streamIcon,
                           'type': VideoType.live,
                           'programTitle': current?.title,
                           'programStart': current?.start,
                           'programEnd': current?.stop,
                        });
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('İzle'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  );
                },
                orElse: () => const SizedBox(), // Show button anyway?
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.favorite_border),
                label: const Text('Favorilere Ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final programsProvider = StreamProvider.family<List<Program>, int>((ref, channelId) {
  return ref.watch(contentRepositoryProvider).watchPrograms(channelId);
});
