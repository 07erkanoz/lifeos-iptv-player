import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/personalized_picks_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/personalized_picks_provider.dart';
import 'package:lifeostv/presentation/widgets/ai/ai_feedback_sheet.dart';
import 'package:lifeostv/presentation/widgets/ai/why_dialog.dart';

/// Dashboard "Sana Özel" rail — passive daily-refresh AI-curated
/// picks based on the user's watch history + favourites.
///
/// Hides itself entirely when:
///   * the user has no Gemini key (provider returns null), or
///   * the AI call failed and there's no cache to fall back to.
///
/// On loading shows a slim shimmer-style placeholder so the
/// dashboard doesn't reflow when the rail lands.
class PersonalizedPicksRail extends ConsumerWidget {
  /// Called when the user taps a poster — usually a navigation
  /// callback that pops the dashboard tab over to the right detail
  /// screen with the channel pinned.
  final void Function(Channel channel) onTap;

  const PersonalizedPicksRail({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPicks = ref.watch(personalizedPicksProvider);
    // SYNCHRONOUS snapshot from SharedPreferences — read on the
    // first frame so the dashboard paints the rail instantly when
    // we have a previous-session snapshot, instead of flashing the
    // shimmer for the duration of the async cache lookup.
    final snapshot = ref.watch(personalizedPicksSnapshotProvider);
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Effective cards to render:
    //   1. If the async provider has data → use that (always fresh).
    //   2. Otherwise (loading / error) → fall back to the sync
    //      snapshot so the user sees the previous rail immediately.
    //   3. No async data + no snapshot → fall through to the shimmer
    //      (genuine first-ever cold start).
    final asyncCards = asyncPicks.asData?.value;
    final cards = asyncCards ?? snapshot;

    if (cards != null) {
      if (cards.isEmpty) return const SizedBox.shrink();
      // True while the async provider is computing on top of stored
      // cards — i.e. user hit refresh and we're waiting for the new
      // Gemini call. Drives the header spinner so the user sees the
      // tap landed instead of staring at an unchanged rail.
      final isRefreshing =
          asyncPicks.isLoading || asyncPicks.isRefreshing;
      return _RailBody(
        cards: cards,
        onTap: onTap,
        title: l10n.dashboardForYouTitle,
        subtitle: l10n.dashboardForYouSubtitle,
        refreshTooltip: l10n.dashboardForYouRefresh,
        onRefresh: () async {
          await ref.read(personalizedPicksRepositoryProvider).clear();
          ref.read(personalizedPicksRefreshSeedProvider.notifier).bump();
        },
        isDark: isDark,
        isRefreshing: isRefreshing,
      );
    }

    // No snapshot + still loading → show the shimmer.
    if (asyncPicks.isLoading) {
      return _LoadingShimmer(
        title: l10n.dashboardForYouTitle,
        subtitle: l10n.dashboardForYouLoading,
        isDark: isDark,
      );
    }
    // No snapshot + error or null data → hide the rail entirely.
    return const SizedBox.shrink();
  }
}

class _RailBody extends StatelessWidget {
  final List<PersonalizedPickCard> cards;
  final void Function(Channel channel) onTap;
  final String title;
  final String subtitle;
  final String refreshTooltip;
  final Future<void> Function()? onRefresh;
  final bool isDark;

  /// True while the rail is showing cached cards AND the async
  /// provider is recomputing fresh ones (user tapped the refresh
  /// button, or `dislikedStreamIdsProvider` invalidated). The
  /// header icon swaps to a spinner so the tap has visible feedback
  /// instead of looking ignored.
  final bool isRefreshing;

  const _RailBody({
    required this.cards,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.refreshTooltip,
    required this.onRefresh,
    required this.isDark,
    this.isRefreshing = false,
  });

  @override
  Widget build(BuildContext context) {
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
                title,
                style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: refreshTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  iconSize: 18,
                  // Disable + swap icon for spinner while a refresh
                  // is in flight. Disabling prevents double-tap
                  // spamming during the 5-15 s Gemini call.
                  onPressed: isRefreshing ? null : () => onRefresh!(),
                  icon: isRefreshing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          color: AppColors.primary,
                        ),
                ),
            ]),
          ),
          SizedBox(
            // Card is 140 wide, poster 140×210 + 100 of text below
            // = ~310 total height including reason text.
            height: 320,
            // ScrollConfiguration override: on Linux/Windows/macOS
            // desktop the default ScrollBehavior excludes mouse drag,
            // so users on a regular cursor cannot pull the rail
            // sideways. We opt mouse + trackpad back in here.
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
                itemBuilder: (context, i) => _PickCard(
                  card: cards[i],
                  onTap: () => onTap(cards[i].channel),
                  isDark: isDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickCard extends StatefulWidget {
  final PersonalizedPickCard card;
  final VoidCallback onTap;
  final bool isDark;

  const _PickCard({
    required this.card,
    required this.onTap,
    required this.isDark,
  });

  @override
  State<_PickCard> createState() => _PickCardState();
}

class _PickCardState extends State<_PickCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ch = widget.card.channel;
    final isActive = _hovered || _focused;
    return Focus(
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      },
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
                  // Feedback overflow menu — always visible so it's
                  // discoverable on touch / TV (where hover doesn't
                  // exist). The button has its own subtle background
                  // and becomes more prominent on the parent card's
                  // hover/focus state via [isActive].
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _FeedbackOverflowButton(
                      streamId: ch.streamId,
                      type: ch.type,
                      title: ch.name,
                      reason: widget.card.reason,
                      feature: 'sanaOzel',
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
                // Reason line — hidden when blank (the fallback
                // path supplies empty reasons so cards stay clean
                // when AI couldn't generate the rail). Tap to expand
                // into the full "Why?" popover with the un-truncated
                // reason and any extra signals (genre overlap, taste
                // profile matches) — useful when the 3-line ellipsis
                // hides the punch line.
                if (widget.card.reason.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  MouseRegion(
                    cursor: SystemMouseCursors.help,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showWhyPopover(context, ch),
                      child: Row(
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
                                color:
                                    AppColors.primary.withValues(alpha: 0.9),
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                height: 1.3,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    AppColors.primary.withValues(alpha: 0.3),
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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

  Widget _placeholderPoster() {
    return Container(
      width: 140,
      height: 210,
      color: AppColors.surfaceElevatedDark,
      child: const Icon(Icons.movie_outlined,
          color: AppColors.textTertiaryDark, size: 36),
    );
  }

  /// Open the "Why was this picked?" popover. Surfaces the full AI
  /// reason text (un-truncated) plus a few derived signal chips so
  /// the user understands the recommendation rather than just sees
  /// it. Chips include genre + content type at minimum; if year is
  /// present we add a "20XX" badge too.
  void _showWhyPopover(BuildContext context, Channel ch) {
    final signals = <String>[];
    if (ch.genre != null && ch.genre!.trim().isNotEmpty) {
      // Keep just the first 2 genres so the row doesn't wrap into
      // four lines on Turkish multi-genre categories like "KOMEDi &
      // ROMANTiK & GENÇLİK".
      final genres = ch.genre!
          .split(RegExp(r'[,&·]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(2);
      signals.addAll(genres);
    }
    if (ch.year != null && ch.year!.trim().isNotEmpty) {
      signals.add(ch.year!.trim());
    }
    if (ch.type == 'series') {
      signals.add('Dizi');
    } else if (ch.type == 'movie') {
      signals.add('Film');
    }
    WhyDialog.show(
      context,
      channel: ch,
      reason: widget.card.reason,
      signals: signals,
      feature: 'Sana Özel',
    );
  }
}

/// Shimmer-shaped placeholder shown while the provider is computing
/// or fetching for the first time. Keeps the dashboard's vertical
/// layout stable so the real rail lands without a reflow.
class _LoadingShimmer extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDark;

  const _LoadingShimmer({
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
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
                title,
                style: TextStyle(
                  color:
                      isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 320,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Container(
                width: 140,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevatedDark
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small overflow-menu button overlayed on AI rail cards. Tapping
/// it opens the [AiFeedbackSheet] — the user can mark "more like
/// this", dismiss the title, or read the AI's reason for picking
/// it. Subtle on purpose: only shown when the parent card is
/// hovered, focused, or being touched.
class _FeedbackOverflowButton extends StatelessWidget {
  final int streamId;
  final String type;
  final String title;
  final String reason;
  final String feature;

  /// When the parent card is hovered / focused, the button gets a
  /// darker background + sharper icon so it stands out as actionable.
  /// At rest it stays visible but understated so it doesn't compete
  /// with the poster art.
  final bool emphasised;

  const _FeedbackOverflowButton({
    required this.streamId,
    required this.type,
    required this.title,
    required this.reason,
    required this.feature,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        // Stronger background so the button reads against bright /
        // busy poster art too — not just dark backgrounds. A pill
        // with primary-tinted border at rest, fully primary on
        // hover/focus.
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
            feature: feature,
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.more_horiz,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}
