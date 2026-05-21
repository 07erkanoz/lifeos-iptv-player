import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/mood_picks_provider.dart';
import 'package:lifeostv/presentation/state/personalized_picks_provider.dart'
    show PersonalizedPickCard;

/// Dashboard "Ruh halin nasıl?" mood-chip selector + lazy rail.
///
/// Hides itself entirely when the user has no Gemini key configured
/// — same convention as the rest of the AI dashboard widgets so the
/// non-AI experience is identical to before this commit.
///
/// Tapping a chip kicks off a one-shot AI call; tapping the same
/// chip again clears the selection and collapses the rail. There is
/// no cache for mood picks — they are deliberately ephemeral.
class MoodSelector extends ConsumerWidget {
  /// Forwarded to whichever pick the user taps in the resulting rail.
  /// Matches the signature used by [PersonalizedPicksRail.onTap].
  final void Function(Channel channel) onTap;

  const MoodSelector({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gemini = ref.watch(geminiServiceProvider);
    if (gemini == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = ref.watch(selectedMoodProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                l10n.moodChipsTitle,
                style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  l10n.moodChipsSubtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ]),
          ),
          // Horizontal chip strip — explicit ScrollConfiguration so
          // desktop mouse drag works alongside touch + trackpad.
          SizedBox(
            height: 44,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: MoodChip.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final mood = MoodChip.values[i];
                  final isSelected = selected == mood;
                  return _MoodChipButton(
                    mood: mood,
                    isSelected: isSelected,
                    isDark: isDark,
                    onTap: () => ref
                        .read(selectedMoodProvider.notifier)
                        .select(mood),
                  );
                },
              ),
            ),
          ),
          if (selected != null)
            _MoodRail(selected: selected, onTap: onTap, isDark: isDark),
        ],
      ),
    );
  }
}

class _MoodChipButton extends StatefulWidget {
  final MoodChip mood;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _MoodChipButton({
    required this.mood,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_MoodChipButton> createState() => _MoodChipButtonState();
}

class _MoodChipButtonState extends State<_MoodChipButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = switch (widget.mood) {
      MoodChip.relax => l10n.moodRelax,
      MoodChip.thrill => l10n.moodThrill,
      MoodChip.laugh => l10n.moodLaugh,
      MoodChip.think => l10n.moodThink,
      MoodChip.nostalgia => l10n.moodNostalgia,
      MoodChip.surprise => l10n.moodSurprise,
    };
    final icon = switch (widget.mood) {
      MoodChip.relax => Icons.spa_outlined,
      MoodChip.thrill => Icons.bolt,
      MoodChip.laugh => Icons.sentiment_very_satisfied,
      MoodChip.think => Icons.psychology,
      MoodChip.nostalgia => Icons.history_edu,
      MoodChip.surprise => Icons.casino,
    };
    final isActive = _hovered || _focused || widget.isSelected;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : (isActive
                      ? AppColors.surfaceElevatedDark
                          .withValues(alpha: 0.8)
                      : AppColors.surfaceElevatedDark
                          .withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.primary
                    : (_focused
                        ? AppColors.primary.withValues(alpha: 0.6)
                        : Colors.transparent),
                width: widget.isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: widget.isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: widget.isSelected
                        ? AppColors.primary
                        : (widget.isDark
                            ? AppColors.textDark
                            : AppColors.textLight),
                    fontSize: 13,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodRail extends ConsumerWidget {
  final MoodChip selected;
  final void Function(Channel) onTap;
  final bool isDark;

  const _MoodRail({
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPicks = ref.watch(moodPicksProvider);
    final l10n = AppLocalizations.of(context)!;
    return asyncPicks.when(
      skipLoadingOnRefresh: false,
      loading: () => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.moodLoading,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ]),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (cards) {
        if (cards == null) return const SizedBox.shrink();
        if (cards.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              l10n.moodEmpty,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 320,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _MoodCard(
                  card: cards[i],
                  onTap: () => onTap(cards[i].channel),
                  isDark: isDark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoodCard extends StatefulWidget {
  final PersonalizedPickCard card;
  final VoidCallback onTap;
  final bool isDark;

  const _MoodCard({
    required this.card,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_MoodCard> createState() => _MoodCardState();
}

class _MoodCardState extends State<_MoodCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.card.channel;
    final isActive = _hovered || _focused;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 140,
            transform: isActive
                ? (Matrix4.identity()..scaleByDouble(1.04, 1.04, 1.04, 1.0))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: _focused
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: ch.streamIcon!,
                          width: 140,
                          height: 210,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _placeholderPoster(),
                        )
                      : _placeholderPoster(),
                ),
                const SizedBox(height: 6),
                Text(
                  ch.name,
                  style: TextStyle(
                    color: widget.isDark
                        ? AppColors.textDark
                        : AppColors.textLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.card.reason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          widget.card.reason,
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.9),
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderPoster() {
    return Container(
      width: 140,
      height: 210,
      color: AppColors.surfaceElevatedDark,
      child: const Icon(Icons.movie_outlined,
          color: AppColors.textTertiaryDark, size: 36),
    );
  }
}
