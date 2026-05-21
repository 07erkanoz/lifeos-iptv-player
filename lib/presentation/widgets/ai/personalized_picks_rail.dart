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

  const _RailBody({
    required this.cards,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.refreshTooltip,
    required this.onRefresh,
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
                  icon: const Icon(
                    Icons.refresh,
                    color: AppColors.primary,
                  ),
                  onPressed: () => onRefresh!(),
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
                // Reason line — hidden when blank (the fallback
                // path supplies empty reasons so cards stay clean
                // when AI couldn't generate the rail).
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
