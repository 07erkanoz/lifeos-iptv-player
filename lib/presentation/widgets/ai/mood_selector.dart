import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/group_mode_provider.dart';
import 'package:lifeostv/presentation/state/mood_picks_provider.dart';
import 'package:lifeostv/presentation/state/personalized_picks_provider.dart'
    show PersonalizedPickCard;
import 'package:lifeostv/presentation/widgets/ai/ai_feedback_sheet.dart';

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
              const SizedBox(width: 10),
              // Group-mode toggle. When armed the chip surfaces the
              // count of profiles in the group; tap to open the
              // multi-select sheet that armed it.
              const _GroupModeChip(),
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
                Stack(children: [
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
                  // Feedback overflow menu — same design as the
                  // "Sana Özel" rail, surfaces "Sevmedim" / "Bunun
                  // gibi daha" / "Neden önerildi?" without leaving
                  // the rail.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _MoodFeedbackButton(
                      streamId: ch.streamId,
                      type: ch.type,
                      title: ch.name,
                      reason: widget.card.reason,
                      emphasised: isActive,
                    ),
                  ),
                ]),
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

/// Small overflow-menu button overlayed on mood rail cards. Same
/// affordance as the "Sana Özel" rail's _FeedbackOverflowButton —
/// kept as its own class here so we don't cross-import private
/// widgets between rail files.
class _MoodFeedbackButton extends StatelessWidget {
  final int streamId;
  final String type;
  final String title;
  final String reason;
  final bool emphasised;

  const _MoodFeedbackButton({
    required this.streamId,
    required this.type,
    required this.title,
    required this.reason,
    required this.emphasised,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: emphasised
            ? AppColors.primary
            : Colors.black.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: emphasised
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => AiFeedbackSheet.show(
            context,
            streamId: streamId,
            type: type,
            title: title,
            reason: reason.isNotEmpty ? reason : null,
            feature: 'mood',
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.more_horiz,
                color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}

/// Compact toggle chip surfaced in the mood selector header. When
/// group mode is off, shows an outlined "Grup" icon. When armed,
/// fills with the primary colour and surfaces the participant
/// count, e.g. "🛡 3 kişi".
///
/// Tap → opens [_GroupModePickerSheet] with the household's full
/// profile list. The user multi-selects 2+ profiles; on save the
/// taste profile aggregates over them and downstream rails
/// (mood / Sana Özel / hero) all rebuild against the new signal.
class _GroupModeChip extends ConsumerWidget {
  const _GroupModeChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupModeProfileIdsProvider);
    final active = group.length >= 2;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _GroupModePickerSheet.show(context),
      onLongPress: active
          ? () => ref.read(groupModeProfileIdsProvider.notifier).clear()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppColors.primary
                : AppColors.borderDark,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.groups : Icons.groups_outlined,
              size: 14,
              color: active
                  ? AppColors.primary
                  : AppColors.textSecondaryDark,
            ),
            const SizedBox(width: 4),
            Text(
              active
                  ? '${group.length} ${l10n.profileGroupShort}'
                  : l10n.profileGroupMode,
              style: TextStyle(
                color: active
                    ? AppColors.primary
                    : AppColors.textSecondaryDark,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet multi-select for assembling a group. Lists every
/// profile and lets the user tick 2+. Clearing → group mode off.
class _GroupModePickerSheet extends ConsumerStatefulWidget {
  const _GroupModePickerSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _GroupModePickerSheet(),
    );
  }

  @override
  ConsumerState<_GroupModePickerSheet> createState() =>
      _GroupModePickerSheetState();
}

class _GroupModePickerSheetState
    extends ConsumerState<_GroupModePickerSheet> {
  late Set<int> _draft;

  @override
  void initState() {
    super.initState();
    final current = ref.read(groupModeProfileIdsProvider);
    final activeId = ref.read(activeProfileIdProvider).value ?? 1;
    _draft = {...current, activeId};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profilesAsync = ref.watch(profilesListProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.textTertiaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              const Icon(Icons.groups, color: AppColors.primary),
              const SizedBox(width: 10),
              Text(
                l10n.profileGroupMode,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              l10n.profileGroupModeDesc,
              style: const TextStyle(
                color: AppColors.textSecondaryDark,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            profilesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('$e'),
              data: (profiles) {
                if (profiles.length < 2) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      l10n.profileGroupNeedsTwo,
                      style: const TextStyle(
                        color: AppColors.textTertiaryDark,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(
                  children: profiles
                      .map((p) => CheckboxListTile(
                            value: _draft.contains(p.id),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _draft.add(p.id);
                                } else {
                                  _draft.remove(p.id);
                                }
                              });
                            },
                            title: Text(p.name),
                            subtitle: p.isKids
                                ? Text(
                                    l10n.profileKids,
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 11,
                                    ),
                                  )
                                : null,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref
                        .read(groupModeProfileIdsProvider.notifier)
                        .clear();
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n.profileGroupClear),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _draft.length >= 2
                      ? () {
                          ref
                              .read(groupModeProfileIdsProvider
                                  .notifier)
                              .set(_draft);
                          Navigator.of(context).pop();
                        }
                      : null,
                  child: Text(l10n.ok),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
