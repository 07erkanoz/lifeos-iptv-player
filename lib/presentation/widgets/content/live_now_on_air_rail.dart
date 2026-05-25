import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Provider for the "Şu an canlıda" rail. Pulls from
/// [ContentRepository.liveNowOnAir] and refreshes itself every
/// minute so the rail follows along as programmes change.
///
/// Implemented as a stream rather than a one-shot future so the
/// minute-interval invalidation is internal to the provider — UI
/// just subscribes and rebuilds on each emit.
final liveNowOnAirProvider =
    StreamProvider<List<({Channel channel, Program program})>>((ref) async* {
  final repo = ref.watch(contentRepositoryProvider);
  yield await repo.liveNowOnAir();
  // Re-emit on every minute boundary so a programme that ends at
  // 21:00 falls off the rail at 21:00:xx, replaced by whatever
  // started at 21:00 on the same channel.
  await for (final _ in Stream<void>.periodic(const Duration(minutes: 1))) {
    yield await repo.liveNowOnAir();
  }
});

/// Horizontally-scrollable rail of channels currently broadcasting,
/// each card showing the channel logo + name + "şu anki program"
/// title. Tap a card → [onTap] receives the channel so the caller
/// can push the player route with the right URL.
///
/// Hides itself when there's no EPG data — no point showing an
/// empty rail. Skeleton placeholder while the first emit is in
/// flight.
class LiveNowOnAirRail extends ConsumerWidget {
  final void Function(Channel channel) onTap;

  const LiveNowOnAirRail({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dataAsync = ref.watch(liveNowOnAirProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.liveNowOnAir,
                style: TextStyle(
                  color:
                      isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  l10n.liveNowOnAirDesc,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 110,
            child: dataAsync.when(
              loading: () => const _LoadingPlaceholder(),
              error: (_, _) => const SizedBox.shrink(),
              data: (rows) {
                if (rows.isEmpty) return const SizedBox.shrink();
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    // Don't autofocus the first card on every paint
                    // — that would steal focus from elsewhere on the
                    // dashboard during periodic minute-tick rebuilds.
                    // Initial focus is up to TvFocusRegistry; once
                    // the rail is in scope the user can D-pad onto
                    // it like any other card.
                    return _NowOnAirCard(
                      channel: rows[i].channel,
                      program: rows[i].program,
                      onTap: () => onTap(rows[i].channel),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NowOnAirCard extends StatefulWidget {
  final Channel channel;
  final Program program;
  final VoidCallback onTap;

  const _NowOnAirCard({
    required this.channel,
    required this.program,
    required this.onTap,
  });

  @override
  State<_NowOnAirCard> createState() => _NowOnAirCardState();
}

class _NowOnAirCardState extends State<_NowOnAirCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _focused || _hovered;
    // Programme progress bar — same math the EPG overlay uses.
    final now = DateTime.now();
    final total =
        widget.program.stop.difference(widget.program.start).inSeconds;
    final elapsed = now.difference(widget.program.start).inSeconds;
    final progress =
        total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;
    final timeRange =
        '${DateFormat('HH:mm').format(widget.program.start)}–${DateFormat('HH:mm').format(widget.program.stop)}';
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
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
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? AppColors.primary
                    : AppColors.borderDark,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: (widget.channel.streamIcon != null &&
                            widget.channel.streamIcon!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: widget.channel.streamIcon!,
                            fit: BoxFit.contain,
                            errorWidget: (_, _, _) =>
                                _logoFallback(),
                          )
                        : _logoFallback(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        // "LIVE" mini badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.channel.name,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        widget.program.title,
                        style: TextStyle(
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeRange,
                        style: const TextStyle(
                          color: AppColors.textTertiaryDark,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.primary),
                          minHeight: 2,
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
    );
  }

  Widget _logoFallback() => Container(
        color: AppColors.surfaceElevatedDark,
        child: const Icon(Icons.tv,
            color: AppColors.textTertiaryDark, size: 22),
      );
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, _) => Container(
        width: 220,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderDark, width: 1),
        ),
      ),
    );
  }
}
