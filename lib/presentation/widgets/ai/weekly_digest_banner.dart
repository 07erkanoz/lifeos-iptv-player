import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/weekly_digest_provider.dart';
import 'package:lifeostv/presentation/widgets/ai/ai_feedback_sheet.dart';

/// Dashboard banner that surfaces the AI weekly digest — newly-added
/// items the AI thinks fit the user's taste.
///
/// Self-hiding policy:
///   * No Gemini key → render nothing.
///   * Provider returned null (no recent additions / AI failed) →
///     render nothing.
///   * User tapped the X within the last 7 days → render nothing
///     (gated by [WeeklyDigest]'s provider).
///
/// Tapping the X writes `lastDigestDismissedAt = now` so the banner
/// stays hidden for the next week.
class WeeklyDigestBanner extends ConsumerWidget {
  final void Function(Channel) onTap;
  const WeeklyDigestBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDigest = ref.watch(weeklyDigestProvider);
    return asyncDigest.when(
      data: (digest) {
        if (digest == null) return const SizedBox.shrink();
        return _DigestCard(digest: digest, onTap: onTap);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _DigestCard extends ConsumerWidget {
  final WeeklyDigest digest;
  final void Function(Channel) onTap;
  const _DigestCard({required this.digest, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.18),
              AppColors.primary.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.weeklyDigestTitle,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        digest.headline,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textDark
                              : AppColors.textLight,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                  color: AppColors.textTertiary(context),
                  tooltip: l10n.weeklyDigestDismiss,
                  onPressed: () {
                    final settings = ref.read(settingsProvider);
                    ref.read(settingsProvider.notifier).updateSettings(
                          settings.copyWith(
                              lastDigestDismissedAt: DateTime.now()),
                        );
                    ref.invalidate(weeklyDigestProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mini poster row.
            SizedBox(
              height: 110,
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
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: digest.channels.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final ch = digest.channels[i];
                    final reason = digest.reasons[ch.streamId] ?? '';
                    return _DigestPosterTile(
                      channel: ch,
                      reason: reason,
                      onTap: () => onTap(ch),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DigestPosterTile extends StatefulWidget {
  final Channel channel;
  final String reason;
  final VoidCallback onTap;
  const _DigestPosterTile({
    required this.channel,
    required this.reason,
    required this.onTap,
  });

  @override
  State<_DigestPosterTile> createState() => _DigestPosterTileState();
}

class _DigestPosterTileState extends State<_DigestPosterTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _hovered || _focused;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: widget.reason,
          waitDuration: const Duration(milliseconds: 400),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 74,
              transform: isActive
                  ? (Matrix4.identity()
                    ..scaleByDouble(1.04, 1.04, 1.04, 1.0))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: _focused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: widget.channel.streamIcon != null &&
                          widget.channel.streamIcon!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.streamIcon!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          memCacheWidth: 720,
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surfaceElevatedDark,
                            child: const Icon(Icons.movie_outlined,
                                color: AppColors.textTertiaryDark,
                                size: 22),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceElevatedDark,
                          child: const Icon(Icons.movie_outlined,
                              color: AppColors.textTertiaryDark, size: 22),
                        ),
                ),
                // Feedback overflow — small but always-visible so
                // the user can dismiss a digest pick without playing
                // it.
                Positioned(
                  top: 2,
                  right: 2,
                  child: _DigestFeedbackButton(
                    streamId: widget.channel.streamId,
                    type: widget.channel.type,
                    title: widget.channel.name,
                    reason: widget.reason,
                    emphasised: isActive,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact overflow-menu button used by the weekly-digest tiles.
/// Smaller than the rail variant because the digest posters are
/// only 74 px wide.
class _DigestFeedbackButton extends StatelessWidget {
  final int streamId;
  final String type;
  final String title;
  final String reason;
  final bool emphasised;

  const _DigestFeedbackButton({
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
              : AppColors.primary.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 3,
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
            feature: 'weeklyDigest',
          ),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.more_horiz,
                color: Colors.white, size: 13),
          ),
        ),
      ),
    );
  }
}
