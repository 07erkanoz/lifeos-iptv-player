import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifeostv/config/theme.dart';

/// A consistent, friendly empty state for screens with no content.
///
/// Replaces the scattered "small icon + one-line text" patterns
/// (search no-results, empty favourites, empty history, blank
/// dashboard rails) with a single illustrated component:
///
///   * Large soft-tinted glyph in a circular halo (96 px) — reads
///     as an illustration rather than a tiny status icon.
///   * Bold one-line headline (the *what*).
///   * Optional muted sub-line (the *why* / *what to do*).
///   * Optional CTA button (the action that fills the void —
///     "İçerik senkronize et", "Aramaya başla", "Bir favori ekle").
///
/// The component intentionally has no hard-coded illustration assets
/// (no SVG / Lottie) so it works in offline builds and on Android TV
/// where image decode cost matters. The colour halo + icon combo
/// gives enough visual weight to feel designed without shipping a
/// 200 KB Lottie file per state.
///
/// Usage:
///   `EmptyState(
///      icon: Icons.favorite_border,
///      title: l10n.noFavorites,
///      subtitle: l10n.noFavoritesHint,
///      actionLabel: l10n.discoverContent,
///      onAction: () => context.go('/movies'),
///    )`
///
/// For the most common shapes there are named constructors at the
/// bottom of this file so callers don't have to repeat boilerplate
/// (icon + colour + sensible defaults).
class EmptyState extends StatelessWidget {
  /// The hero glyph shown inside the circular halo. Use the outlined
  /// variants (e.g. `Icons.favorite_border`, `Icons.search_off`) —
  /// solid icons look too heavy at 56 px.
  final IconData icon;

  /// One-line bold headline. Localised by caller.
  final String title;

  /// Optional muted description below the title. Two-line max — the
  /// component truncates with ellipsis so callers don't have to
  /// rewrite for narrow screens.
  final String? subtitle;

  /// Optional CTA button label. Both [actionLabel] and [onAction]
  /// must be non-null for the button to render.
  final String? actionLabel;

  /// Optional CTA handler. See [actionLabel].
  final VoidCallback? onAction;

  /// Accent colour for the halo + glyph. Defaults to the app's
  /// primary brand colour. Pass a different colour to signal severity
  /// (e.g. `Colors.orange` for "syncing failed" vs the default
  /// brand colour for "no content").
  final Color? accent;

  /// Whether to centre the column vertically in the available space.
  /// `true` for full-screen empties (search no-results), `false`
  /// when the empty state is being embedded inside a card or rail
  /// (caller takes care of centring).
  final bool fillParent;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accent,
    this.fillParent = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = accent ?? AppColors.primary;
    final titleColor = isDark ? AppColors.textDark : AppColors.textLight;
    final subColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    final hasAction = actionLabel != null && onAction != null;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Halo + glyph ───────────────────────────────────────────
        // Three nested circles for soft layered glow without the cost
        // of a real shadow blur. Reads as an illustration on both
        // dark and light themes.
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor.withValues(alpha: 0.06),
          ),
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.10),
              ),
              child: Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.16),
                  ),
                  child: Icon(icon, size: 32, color: accentColor),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Headline ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),

        // ── Subtitle ──────────────────────────────────────────────
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subColor,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],

        // ── CTA ───────────────────────────────────────────────────
        // autofocus so Android TV remote lands here when an empty
        // state is reached — without it the screen has no focusable
        // element, leaving the user stranded with no D-pad target.
        if (hasAction) ...[
          const SizedBox(height: 20),
          _EmptyStateCta(
            label: actionLabel!,
            color: accentColor,
            onTap: onAction!,
          ),
        ],
      ],
    );

    if (!fillParent) return body;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: body,
      ),
    );
  }

  // ──────────────────────── Named constructors ────────────────────
  // Sensible-default factories for the most common empty states.
  // Callers get a one-liner without having to remember which icon
  // pairs with which state.

  /// Search returned no results. Magnifying-glass-off glyph, neutral
  /// accent, asks the user to refine their query.
  factory EmptyState.search({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    bool fillParent = true,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.search_off_rounded,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
        accent: AppColors.accent,
        fillParent: fillParent,
      );

  /// Empty favourites list. Heart-outline glyph, brand accent.
  factory EmptyState.favorites({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.favorite_border_rounded,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// Empty watch history. Clock-outline glyph.
  factory EmptyState.history({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.history_rounded,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// Dashboard rail with no AI / curated content yet. Sparkle glyph
  /// to hint that the rail is AI-powered and will fill in after a
  /// few interactions.
  factory EmptyState.aiCold({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.auto_awesome,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
      );

  /// Library completely empty (pre-sync). Movie-reel glyph, prompts
  /// the user to kick off a sync.
  factory EmptyState.library({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.movie_filter_outlined,
        title: title,
        subtitle: subtitle,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

/// CTA button inside [EmptyState]. Wrapped in Focus + autofocus so
/// Android TV / keyboard users have a guaranteed initial target on
/// every empty screen. ElevatedButton already supports focus
/// internally, but its default visual is subtle on 10-foot UIs —
/// this wrapper bumps the border width on focus so the focused
/// state is unmistakable from across the room.
class _EmptyStateCta extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _EmptyStateCta({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_EmptyStateCta> createState() => _EmptyStateCtaState();
}

class _EmptyStateCtaState extends State<_EmptyStateCta> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
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
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? Colors.white
                  : widget.color.withValues(alpha: 0.0),
              width: _focused ? 2.5 : 0,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
