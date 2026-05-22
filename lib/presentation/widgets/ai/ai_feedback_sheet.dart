import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/ai_feedback_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Bottom-sheet action menu that opens when the user taps the ⋯
/// button on any AI recommendation card. Lets them tell the AI how
/// it did:
///
///   * **Sevmedim** — never resurface this title in any AI rail.
///     Stored as a `dislike` row in `ai_feedback`. Hard exclusion.
///   * **Bunun gibi daha** — boost this title as a taste anchor in
///     future AI prompts. Stored as `moreLike`.
///   * **Neden önerildi?** — show the AI's own reason text in a
///     readable dialog. No persistence; just transparency.
///
/// Both toggles flip on/off — re-tapping "Sevmedim" on a disliked
/// title undoes the dislike. Dislike + moreLike are mutually
/// exclusive (toggling one clears the other) so the table never
/// holds contradictory signals.
class AiFeedbackSheet extends ConsumerWidget {
  final int streamId;
  final String type;
  final String title;
  final String? reason;
  final String? feature;

  const AiFeedbackSheet({
    super.key,
    required this.streamId,
    required this.type,
    required this.title,
    this.reason,
    this.feature,
  });

  static Future<void> show(
    BuildContext context, {
    required int streamId,
    required String type,
    required String title,
    String? reason,
    String? feature,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiFeedbackSheet(
        streamId: streamId,
        type: type,
        title: title,
        reason: reason,
        feature: feature,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final repo = ref.watch(aiFeedbackRepositoryProvider);
    return Container(
      decoration: BoxDecoration(
        color:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: StreamBuilder<({bool disliked, bool moreLike})>(
          stream: repo.watchFlags(streamId: streamId, type: type),
          builder: (context, snapshot) {
            final flags =
                snapshot.data ?? (disliked: false, moreLike: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title line — what we're giving feedback ON.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textDark
                          : AppColors.textLight,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const Divider(height: 1),
                _ActionTile(
                  icon: flags.moreLike
                      ? Icons.thumb_up
                      : Icons.thumb_up_outlined,
                  label: l10n.aiFeedbackMoreLike,
                  highlighted: flags.moreLike,
                  onTap: () async {
                    final added = await repo.toggle(
                      streamId: streamId,
                      type: type,
                      action: AiFeedbackAction.moreLike,
                      feature: feature,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(added
                          ? l10n.aiFeedbackMoreLikeAdded
                          : l10n.aiFeedbackRemoved),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
                _ActionTile(
                  icon: flags.disliked
                      ? Icons.thumb_down
                      : Icons.thumb_down_outlined,
                  label: l10n.aiFeedbackDislike,
                  highlighted: flags.disliked,
                  destructive: !flags.disliked,
                  onTap: () async {
                    final added = await repo.toggle(
                      streamId: streamId,
                      type: type,
                      action: AiFeedbackAction.dislike,
                      feature: feature,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(added
                          ? l10n.aiFeedbackDislikeAdded
                          : l10n.aiFeedbackRemoved),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                ),
                if (reason != null && reason!.trim().isNotEmpty) ...[
                  const Divider(height: 1),
                  _ActionTile(
                    icon: Icons.info_outline,
                    label: l10n.aiFeedbackWhy,
                    onTap: () {
                      Navigator.of(context).pop();
                      showDialog<void>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          backgroundColor: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          title: Row(children: [
                            const Icon(Icons.auto_awesome,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ]),
                          content: Text(
                            reason!,
                            style: TextStyle(
                              color: isDark
                                  ? AppColors.textDark
                                  : AppColors.textLight,
                              height: 1.5,
                              fontSize: 14,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(),
                              child: Text(l10n.close),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  final bool destructive;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconColor;
    final Color textColor;
    if (highlighted) {
      iconColor = AppColors.primary;
      textColor = AppColors.primary;
    } else if (destructive) {
      iconColor = AppColors.textSecondary(context);
      textColor =
          isDark ? AppColors.textDark : AppColors.textLight;
    } else {
      iconColor = AppColors.textSecondary(context);
      textColor =
          isDark ? AppColors.textDark : AppColors.textLight;
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight:
                  highlighted ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }
}
