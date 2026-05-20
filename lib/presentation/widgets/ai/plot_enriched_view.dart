import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Plot text + small inline AI action links.
///
/// Drop-in replacement for the `Text(plot)` widgets currently used
/// on movie + series detail pages. Behaviour:
///
///   * When the user has *no* Gemini key configured: behaves
///     exactly like the original `Text` widget — no actions, no
///     visual difference, no extra space.
///   * When a key is configured: renders the plot followed by a
///     small italic row of primary-coloured inline links:
///       – "Türkçe'ye çevir" (if the plot has text)
///       – "Spoiler-free özet" (if plot length > 250 chars)
///       – "Plot bilgisi getir" (if plot is empty / very short)
///     Tapping any link replaces the plot text with the AI output
///     and swaps the link row for a single "Orijinali göster" link
///     so the user can revert.
///
/// Side-channel design:
///   * The widget stores enrichment in-memory only for the current
///     Channel id. If the user switches to another detail page and
///     returns, enrichment is re-fetched. A future commit can
///     persist enrichments per-channel in Drift; not needed for v1.
///   * No spinner overlay — the action row turns into a compact
///     "Hazırlıyor…" pill so layout doesn't jump.
///   * Failures stay quiet: on null response, the link row shows
///     "Alınamadı — tekrar dene" and the original plot stays.
class PlotEnrichedView extends ConsumerStatefulWidget {
  /// The channel whose plot we're rendering. Used for AI context
  /// (title, year, genre) — we don't *change* anything on the
  /// channel itself.
  final Channel channel;

  /// The plot text currently being displayed. May come from a fresh
  /// API fetch (`_vodInfo`) rather than `channel.plot`, so we accept
  /// it explicitly instead of always reading `channel.plot`. Passed
  /// to the AI as the source-of-truth for translate/summarise.
  final String plotText;

  /// Style applied to the plot text. Caller supplies the same
  /// `TextStyle` it used for the `Text(plot)` widget being replaced
  /// so the substitution is visually invisible when no key is set.
  final TextStyle? textStyle;

  /// Optional max-lines limit for the rendered plot. The action
  /// links sit underneath the (possibly truncated) text.
  final int? maxLines;

  /// Optional overflow for the plot text.
  final TextOverflow? overflow;

  const PlotEnrichedView({
    super.key,
    required this.channel,
    required this.plotText,
    this.textStyle,
    this.maxLines,
    this.overflow,
  });

  @override
  ConsumerState<PlotEnrichedView> createState() => _PlotEnrichedViewState();
}

class _PlotEnrichedViewState extends ConsumerState<PlotEnrichedView> {
  /// When non-null, this replaces the original plot text in the UI.
  /// Stays in memory until the widget is rebuilt with a different
  /// channel (didUpdateWidget clears it).
  String? _enriched;

  /// Mode the current `_enriched` text came from. Drives the "AI" tag
  /// suffix (some modes deserve different labels in future).
  PlotEnrichMode? _enrichedMode;

  bool _loading = false;
  bool _lastCallFailed = false;

  @override
  void didUpdateWidget(covariant PlotEnrichedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.streamId != widget.channel.streamId) {
      // Different content — drop any stale enrichment.
      _enriched = null;
      _enrichedMode = null;
      _loading = false;
      _lastCallFailed = false;
    }
  }

  /// ISO-639-1 code for the language the user reads the app in.
  /// Mirrors how the subtitle plumbing resolves user language so the
  /// AI's reply matches the rest of the UI's localization.
  String _userLanguageCode() {
    final appLang = ref.read(settingsProvider).language;
    if (appLang == AppLanguage.system) {
      return Localizations.localeOf(context).languageCode;
    }
    return appLang.name;
  }

  Future<void> _enrich(PlotEnrichMode mode) async {
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) return;
    setState(() {
      _loading = true;
      _lastCallFailed = false;
    });
    final result = await gemini.enrichPlot(
      title: widget.channel.name,
      year: widget.channel.year,
      genre: widget.channel.genre,
      originalPlot: widget.plotText,
      mode: mode,
      targetLanguage: _userLanguageCode(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null || result.isEmpty) {
        _lastCallFailed = true;
      } else {
        _enriched = result;
        _enrichedMode = mode;
      }
    });
  }

  void _revertToOriginal() {
    setState(() {
      _enriched = null;
      _enrichedMode = null;
      _lastCallFailed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAiKey = ref.watch(settingsProvider).hasAiKey;
    final original = widget.plotText;
    final plotIsLong = original.length > 250;
    final plotIsEmpty = original.trim().isEmpty;
    final isShowingEnriched = _enriched != null;
    final displayText = isShowingEnriched ? _enriched! : original;

    // The original "Text(plot)" without a key — same dimensions,
    // same style. Skipping this branch entirely (rather than just
    // building an empty SizedBox) so no spacing creeps in.
    if (!hasAiKey && plotIsEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The plot text itself. Wrapped in an AnimatedSwitcher so the
        // swap between original and enriched feels intentional (a
        // 200 ms cross-fade), not abrupt.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: displayText.isEmpty
              ? const SizedBox.shrink()
              : RichText(
                  key: ValueKey('plot-${widget.channel.streamId}-$isShowingEnriched'),
                  maxLines: widget.maxLines,
                  overflow:
                      widget.overflow ?? TextOverflow.clip,
                  text: TextSpan(
                    style: widget.textStyle,
                    children: [
                      if (isShowingEnriched) ...[
                        TextSpan(
                          text:
                              '${AppLocalizations.of(context)!.aiPlotEnrichedTag} ✨  ',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: (widget.textStyle?.fontSize ?? 13) - 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                      TextSpan(text: displayText),
                    ],
                  ),
                ),
        ),
        // Action / status row. Only renders when the user has a key
        // — keeps the no-key path pixel-identical to the previous
        // bare-Text widget.
        if (hasAiKey)
          Padding(
            padding: EdgeInsets.only(top: displayText.isEmpty ? 0 : 8),
            child: _ActionRow(
              showTranslate: !plotIsEmpty && !isShowingEnriched,
              showSummarize: plotIsLong && !isShowingEnriched,
              showFillIn: plotIsEmpty && !isShowingEnriched,
              showRevert: isShowingEnriched,
              loading: _loading,
              failed: _lastCallFailed,
              onTranslate: () => _enrich(PlotEnrichMode.translate),
              onSummarize: () => _enrich(PlotEnrichMode.summarize),
              onFillIn: () => _enrich(PlotEnrichMode.fillIn),
              onRevert: _revertToOriginal,
              activeMode: _enrichedMode,
            ),
          ),
      ],
    );
  }
}

/// Compact row of inline italic links under the plot. Each link is
/// a [_InlineLink] — no chip outline, no icon, just primary-coloured
/// text in a Wrap so it reflows on narrow viewports.
class _ActionRow extends StatelessWidget {
  final bool showTranslate;
  final bool showSummarize;
  final bool showFillIn;
  final bool showRevert;
  final bool loading;
  final bool failed;
  final VoidCallback onTranslate;
  final VoidCallback onSummarize;
  final VoidCallback onFillIn;
  final VoidCallback onRevert;
  final PlotEnrichMode? activeMode;

  const _ActionRow({
    required this.showTranslate,
    required this.showSummarize,
    required this.showFillIn,
    required this.showRevert,
    required this.loading,
    required this.failed,
    required this.onTranslate,
    required this.onSummarize,
    required this.onFillIn,
    required this.onRevert,
    required this.activeMode,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (loading) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
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
      ]);
    }

    final links = <Widget>[];
    if (showTranslate) {
      links.add(_InlineLink(label: l10n.aiPlotTranslate, onTap: onTranslate));
    }
    if (showSummarize) {
      links.add(_InlineLink(label: l10n.aiPlotSummarize, onTap: onSummarize));
    }
    if (showFillIn) {
      links.add(_InlineLink(label: l10n.aiPlotFillIn, onTap: onFillIn));
    }
    if (showRevert) {
      links.add(_InlineLink(label: l10n.aiPlotShowOriginal, onTap: onRevert));
    }
    if (failed) {
      // Inline error — gentle. User can tap any of the visible links
      // again to retry.
      links.add(Text(
        l10n.aiPlotError,
        style: const TextStyle(
          color: AppColors.warning,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ));
    }

    if (links.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: links,
    );
  }
}

class _InlineLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _InlineLink({required this.label, required this.onTap});

  @override
  State<_InlineLink> createState() => _InlineLinkState();
}

class _InlineLinkState extends State<_InlineLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontStyle: FontStyle.italic,
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
