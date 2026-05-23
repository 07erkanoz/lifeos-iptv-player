import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// "Why?" popover — shows the AI's full un-truncated rationale for
/// why a card was recommended, plus the contextual signals that
/// went into the pick (genre overlap, taste profile, time of day,
/// mood, etc.).
///
/// Surfaced by tapping the small reason text under any AI-curated
/// card (Sana Özel, mood, hero, chat). The card's reason text is
/// already shown 3-line truncated under the poster — this dialog
/// gives the full text plus extra signals so the user understands
/// why this particular title was placed in front of them.
///
/// Distinct from [AiFeedbackSheet]: that sheet is the
/// dislike / more-like-this action menu; this one is read-only and
/// optimised for one-tap exit. We deliberately do NOT include
/// feedback buttons here so the dialog is a clean explanation and
/// doesn't compete with the existing ⋯ menu.
class WhyDialog extends StatelessWidget {
  /// The channel being explained. Used for poster + title header.
  final Channel channel;

  /// The full AI reason text — no truncation.
  final String reason;

  /// Optional list of extra signal tags ("Kore dizisi", "Yönetmen:
  /// Bong Joon-ho", "Akşam saatleri için uygun") — anything the
  /// caller wants to surface as small chips above the reason.
  final List<String> signals;

  /// Optional match percentage (0–100). When set, renders a colour-
  /// coded "%87 uyumlu" badge in the header. Caller computes this
  /// from the TasteProfile signal strength × category match (see
  /// `taste_profile.dart`).
  final int? matchPercent;

  /// Which AI feature surfaced this card. Pure debugging affordance,
  /// not user-facing — used by an "AI tarafından sağlandı: sanaOzel"
  /// muted footnote so the user knows which rail asked the AI.
  final String feature;

  const WhyDialog({
    super.key,
    required this.channel,
    required this.reason,
    this.signals = const [],
    this.matchPercent,
    this.feature = '',
  });

  /// Convenience opener — wraps the standard `showDialog` call so
  /// callers don't have to remember the barrier/route configuration.
  static Future<void> show(
    BuildContext context, {
    required Channel channel,
    required String reason,
    List<String> signals = const [],
    int? matchPercent,
    String feature = '',
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => WhyDialog(
        channel: channel,
        reason: reason,
        signals: signals,
        matchPercent: matchPercent,
        feature: feature,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textDark : AppColors.textLight;
    final subColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final bgColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    // Esc / back key dismisses on every platform (desktop kbd, web,
    // Android TV remote BACK). CallbackShortcuts is the lightest
    // primitive that covers all three without pulling Actions/
    // Intents into a transient dialog.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            Navigator.of(context).maybePop(),
      },
      child: Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: small poster + title + match badge ────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: channel.streamIcon != null &&
                            channel.streamIcon!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: channel.streamIcon!,
                            width: 56,
                            height: 84,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                _placeholderPoster(),
                          )
                        : _placeholderPoster(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.aiFeedbackWhy,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          channel.name,
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (matchPercent != null) ...[
                          const SizedBox(height: 8),
                          _MatchBadge(percent: matchPercent!),
                        ],
                      ],
                    ),
                  ),
                  // autofocus so Android TV / keyboard users land
                  // here when the dialog opens — enter/select then
                  // dismisses, matching the Esc / back binding above.
                  IconButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        Icon(Icons.close, color: subColor, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Reason body ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  reason,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13.5,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

              // ── Signal chips (genre / actor / mood etc.) ──────
              if (signals.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: signals
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: subColor.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              s,
                              style: TextStyle(
                                color: subColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],

              // ── Footnote ─────────────────────────────────────
              if (feature.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '${l10n.aiFeedbackSource}: $feature',
                  style: TextStyle(
                    color: subColor.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _placeholderPoster() => Container(
        width: 56,
        height: 84,
        color: AppColors.surfaceElevatedDark,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.textTertiaryDark, size: 18),
      );
}

/// "%87 uyumlu" badge — colour-coded:
///   * ≥ 80 → green (strong match)
///   * 60-79 → amber (medium)
///   * < 60 → grey (weak / cold-start)
///
/// Mirrors the colour vocabulary Netflix uses on its own match score
/// while staying inside our existing AppColors palette.
class _MatchBadge extends StatelessWidget {
  final int percent;

  const _MatchBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (percent >= 80) {
      color = Colors.greenAccent.shade400;
    } else if (percent >= 60) {
      color = Colors.amberAccent.shade400;
    } else {
      color = AppColors.textTertiaryDark;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '%$percent ${AppLocalizations.of(context)!.aiMatchScoreSuffix}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
