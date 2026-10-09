import 'package:lifeostv/presentation/state/locale_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Modal bottom sheet that opens when the user taps an actor /
/// director chip on a detail page.
///
/// Renders three layered panels, top-down:
///   1. A header with the person's name.
///   2. An AI-generated career-summary paragraph (hidden when the
///      user has no Gemini key or the AI call returned empty).
///   3. A poster grid of every other title in the user's library
///      featuring this person (both cast and director matches).
///
/// Tapping a poster pops the sheet AND calls back with the matched
/// channel so the host detail page can switch to that title.
class CastDeepDiveSheet extends ConsumerStatefulWidget {
  /// The cast / director name the user tapped.
  final String name;

  /// The title where they clicked the name (e.g. the current movie)
  /// — fed to Gemini as grounding context. Optional.
  final String? appearsInTitle;

  /// Called when the user taps one of the library poster tiles.
  /// The sheet pops itself first, then invokes this so the parent
  /// detail page can navigate cleanly.
  final void Function(Channel)? onChannelTap;

  const CastDeepDiveSheet({
    super.key,
    required this.name,
    this.appearsInTitle,
    this.onChannelTap,
  });

  static Future<void> show(
    BuildContext context, {
    required String name,
    String? appearsInTitle,
    void Function(Channel)? onChannelTap,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      builder: (ctx) => CastDeepDiveSheet(
        name: name,
        appearsInTitle: appearsInTitle,
        onChannelTap: onChannelTap,
      ),
    );
  }

  @override
  ConsumerState<CastDeepDiveSheet> createState() => _CastDeepDiveSheetState();
}

class _CastDeepDiveSheetState extends ConsumerState<CastDeepDiveSheet> {
  String? _summary;
  bool _loadingSummary = false;
  List<Channel> _appearances = const [];
  bool _loadingAppearances = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAppearances();
      _loadAiSummary();
    });
  }

  Future<void> _loadAppearances() async {
    try {
      final repo = ref.read(contentRepositoryProvider);
      final rows = await repo.searchChannelsByCastMember(widget.name);
      if (!mounted) return;
      setState(() {
        _appearances = rows;
        _loadingAppearances = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appearances = const [];
        _loadingAppearances = false;
      });
    }
  }

  Future<void> _loadAiSummary() async {
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) return;
    setState(() => _loadingSummary = true);
    try {
      final lang = ref.read(resolvedLocaleProvider).languageCode;
      final text = await gemini
          .actorCareerSummary(
            name: widget.name,
            appearsInTitle: widget.appearsInTitle,
            targetLanguage: lang,
          )
          .timeout(const Duration(seconds: 12), onTimeout: () => null);
      if (!mounted) return;
      setState(() {
        _summary = (text == null || text.trim().isEmpty) ? null : text;
        _loadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAi = ref.watch(geminiServiceProvider) != null;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            // Header: avatar circle + name + close.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: TextStyle(
                            color: isDark
                                ? AppColors.textDark
                                : AppColors.textLight,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _loadingAppearances
                              ? l10n.castSheetLoadingAppearances
                              : l10n.castSheetAppearancesCount(
                                  _appearances.length,
                                ),
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: AppColors.textTertiary(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  // ── AI career summary ─────────────────────────
                  if (hasAi) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.castSheetAiSummary,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingSummary)
                      Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.castSheetAiLoading,
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    else if (_summary != null)
                      Text(
                        _summary!,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textDark
                              : AppColors.textLight,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      )
                    else
                      Text(
                        l10n.castSheetAiUnavailable,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  // ── Library appearances grid ──────────────────
                  Row(
                    children: [
                      const Icon(
                        Icons.collections_bookmark_outlined,
                        color: AppColors.primary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.castSheetLibraryAppearances,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingAppearances)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else if (_appearances.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.castSheetNoAppearances,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    _buildAppearancesGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearancesGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 600
            ? 5
            : constraints.maxWidth >= 380
            ? 4
            : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 2 / 3.2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: _appearances.length,
          itemBuilder: (context, i) {
            final ch = _appearances[i];
            return GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                widget.onChannelTap?.call(ch);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: ch.streamIcon!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              memCacheWidth: 360,
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.surfaceElevatedDark,
                                child: const Icon(
                                  Icons.movie_outlined,
                                  color: AppColors.textTertiaryDark,
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceElevatedDark,
                              child: const Icon(
                                Icons.movie_outlined,
                                color: AppColors.textTertiaryDark,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ch.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Splits a raw cast / director string into individual person
/// names and renders them as a Wrap of tappable chips.
///
/// The Xtream metadata typically uses ", " as the delimiter, but
/// occasional rows use " · " or " & " — we handle all three. We
/// also collapse the role-suffix noise ("Tom Hanks (voice)" →
/// "Tom Hanks") so the chip label stays clean.
class CastChipRow extends StatelessWidget {
  /// Raw comma/dot-separated string from the channel metadata.
  final String raw;

  /// The current title the user is viewing — passed to Gemini as
  /// grounding context for the actor summary.
  final String? currentTitle;

  /// Forwarded to the sheet — invoked when the user taps a poster
  /// from the library appearances grid.
  final void Function(Channel)? onChannelTap;

  const CastChipRow({
    super.key,
    required this.raw,
    this.currentTitle,
    this.onChannelTap,
  });

  static List<String> splitNames(String raw) {
    final parts = raw
        .split(RegExp(r'[,·&]'))
        .map((s) => s.trim())
        // Strip role-suffix parentheticals (voice, narrator, …).
        .map((s) => s.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '').trim())
        // Strip "as <Role>" suffixes some catalogues use.
        .map(
          (s) => s
              .replaceFirst(RegExp(r'\s+as\s+.*$', caseSensitive: false), '')
              .trim(),
        )
        .where((s) => s.length >= 2)
        .toList();
    // Dedupe preserving order.
    final seen = <String>{};
    final out = <String>[];
    for (final n in parts) {
      final k = n.toLowerCase();
      if (seen.add(k)) out.add(n);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final names = splitNames(raw);
    if (names.isEmpty) {
      return Text(
        raw,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          height: 1.4,
        ),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final name in names)
          _CastChip(
            name: name,
            onTap: () => CastDeepDiveSheet.show(
              context,
              name: name,
              appearsInTitle: currentTitle,
              onChannelTap: onChannelTap,
            ),
          ),
      ],
    );
  }
}

class _CastChip extends StatefulWidget {
  final String name;
  final VoidCallback onTap;
  const _CastChip({required this.name, required this.onTap});

  @override
  State<_CastChip> createState() => _CastChipState();
}

class _CastChipState extends State<_CastChip> {
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
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.3),
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              widget.name,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
