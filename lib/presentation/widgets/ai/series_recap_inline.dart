import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Inline "Şimdiye kadar olanı hatırlat" widget for series detail
/// pages.
///
/// Renders nothing when:
///   * The user has no Gemini key configured, or
///   * No watch progress exists (`nextEpisodeLabel` empty)
///
/// In either case the widget contributes zero pixels and the action
/// button row above stays flush against the plot below.
///
/// When eligible: shows a small italic "Şimdiye kadar olanı hatırlat"
/// link in the same visual language as the plot enrichment links.
/// Tap → loading state → 3-5 paragraph recap inline-expands below.
/// Tap "Özeti gizle" → collapses back.
///
/// Like the plot enrichment widget, this caches in-memory only — a
/// new tap fetches fresh from Gemini. (Future commit could persist
/// per-series in Drift.)
class SeriesRecapInline extends ConsumerStatefulWidget {
  /// The series whose detail page we're on. Used for AI prompt
  /// context (title, year, genre, plot).
  final Channel series;

  /// Label of the episode the user is *about to* play, e.g. "S1E10".
  /// The recap covers everything strictly before this episode.
  final String nextEpisodeLabel;

  /// Auto-fetch and expand on mount instead of waiting for a tap.
  ///
  /// Caller sets this true when the user has been away from this
  /// series for a long time (default threshold: 7 days). The pre-
  /// play "Son izlemende olanlar" auto-pause flow uses this to nudge
  /// the user with a summary the moment they open the detail page.
  /// When false (the default), the user has to tap to expand —
  /// keeps the surface quiet for someone bingeing daily.
  final bool autoExpand;

  /// Optional hint string shown above the expand link when
  /// [autoExpand] is true, e.g. "Son izlemenden 12 gün geçti".
  /// Caller computes from [PlaybackProgress.updatedAt].
  final String? autoExpandHint;

  const SeriesRecapInline({
    super.key,
    required this.series,
    required this.nextEpisodeLabel,
    this.autoExpand = false,
    this.autoExpandHint,
  });

  @override
  ConsumerState<SeriesRecapInline> createState() =>
      _SeriesRecapInlineState();
}

class _SeriesRecapInlineState extends ConsumerState<SeriesRecapInline> {
  String? _recap;
  bool _loading = false;
  bool _failed = false;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant SeriesRecapInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset state when the series or the up-to point changes — a
    // recap for S1E5 is wrong when the user is now resuming at
    // S1E10.
    if (oldWidget.series.streamId != widget.series.streamId ||
        oldWidget.nextEpisodeLabel != widget.nextEpisodeLabel) {
      _recap = null;
      _loading = false;
      _failed = false;
      _expanded = false;
    }
  }

  String _userLanguageCode() {
    final appLang = ref.read(settingsProvider).language;
    if (appLang == AppLanguage.system) {
      return Localizations.localeOf(context).languageCode;
    }
    return appLang.name;
  }

  Future<void> _fetchRecap() async {
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) return;
    setState(() {
      _loading = true;
      _failed = false;
      _expanded = true; // expand immediately to show progress
    });
    final result = await gemini.recapSeriesUpTo(
      title: widget.series.name,
      year: widget.series.year,
      genre: widget.series.genre,
      plot: widget.series.plot,
      nextEpisodeLabel: widget.nextEpisodeLabel,
      targetLanguage: _userLanguageCode(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null || result.isEmpty) {
        _failed = true;
      } else {
        _recap = result;
      }
    });
  }

  void _toggleCollapse() {
    setState(() {
      _expanded = false;
    });
  }

  @override
  void initState() {
    super.initState();
    // Auto-pause behaviour — if the caller flagged this as a "long
    // time since last watched" situation, fetch + expand the recap
    // automatically so the user sees what happened before they
    // click play. Wrapped in a post-frame so we don't fire inside
    // build (Riverpod will throw if we touch providers too early).
    //
    // Defensive gate: if the user doesn't have an AI key configured
    // the build() branch already returns SizedBox.shrink(), but
    // initState still runs. Skipping the fetch here avoids burning
    // a Gemini call attempt that we know will short-circuit at the
    // service layer anyway.
    if (widget.autoExpand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final hasAiKey = ref.read(settingsProvider).hasAiKey;
        if (!hasAiKey) return;
        _fetchRecap();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAiKey = ref.watch(settingsProvider).hasAiKey;
    if (!hasAiKey || widget.nextEpisodeLabel.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;

    // Collapsed: a single italic link. Tapping starts the fetch
    // and reveals the expanded panel in the same setState.
    if (!_expanded) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _RecapLink(
          label: l10n.aiRecapPrompt,
          onTap: () {
            if (_recap == null && !_loading) {
              _fetchRecap();
            } else {
              setState(() => _expanded = true);
            }
          },
        ),
      );
    }

    // Expanded: panel with loading / content / failure state, plus
    // a "Gizle" link at the bottom.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.history_edu_outlined,
                  color: AppColors.primary.withValues(alpha: 0.9), size: 16),
              const SizedBox(width: 8),
              Text(
                '${l10n.aiRecapTag} ✨  ${widget.nextEpisodeLabel}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ]),
            // Auto-expand hint — caller passes a "N gün önce
            // izledin" string when the user is returning to a
            // series they haven't touched in a while, justifying
            // why we proactively opened the recap.
            if (widget.autoExpand &&
                widget.autoExpandHint != null &&
                widget.autoExpandHint!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.autoExpandHint!,
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.aiPlotEnriching,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ])
            else if (_failed)
              Text(
                l10n.aiPlotError,
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (_recap != null)
              // Long AI recaps (400+ words for late-series catch-up)
              // were overflowing the detail page on TV — no scroll
              // wrapper, the bottom half just vanished off-screen.
              // Cap the recap area at 30 % of viewport height and
              // make it scrollable so the user can D-pad / mouse-
              // wheel through it.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height * 0.30,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _recap!,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _RecapLink(label: l10n.aiRecapHide, onTap: _toggleCollapse),
          ],
        ),
      ),
    );
  }
}

class _RecapLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _RecapLink({required this.label, required this.onTap});

  @override
  State<_RecapLink> createState() => _RecapLinkState();
}

class _RecapLinkState extends State<_RecapLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isActive = _hovered || _focused;
    return Focus(
      // D-pad / keyboard support — Android TV users couldn't open
      // the recap without this. Enter/select activates.
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
          child: Container(
            // 8 dp vertical padding bumps the touch target on
            // phones past 36 dp without disturbing desktop layout.
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: _focused
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(
                Icons.history_edu_outlined,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  decoration:
                      isActive ? TextDecoration.underline : null,
                  decorationColor: AppColors.primary,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
