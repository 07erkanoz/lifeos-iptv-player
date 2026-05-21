import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/tonight_recommendation.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/state/tonight_context_provider.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/utils/stream_url_builder.dart';

/// "Bu akşam ne izleyim?" chat sheet.
///
/// Open via `showModalBottomSheet(builder: (_) => const TonightChatSheet())`.
/// The sheet:
///   1. Loads a fresh `TonightContext` (library sample + history + favs).
///   2. Shows a greeting + suggestion chips on first open.
///   3. Renders each turn as a chat bubble; AI bubbles can carry
///      a list of recommendation cards inline.
///   4. Multi-turn — follow-ups reuse the same context snapshot so
///      the user can iterate ("daha kısa bir şey", "drama dışında")
///      without re-fetching.
class TonightChatSheet extends ConsumerStatefulWidget {
  const TonightChatSheet({super.key});

  @override
  ConsumerState<TonightChatSheet> createState() => _TonightChatSheetState();
}

class _TonightChatSheetState extends ConsumerState<TonightChatSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _waitingForAi = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Send the current input (or a suggestion chip's text) as a user
  /// message and kick off the Gemini call. Multi-turn: the entire
  /// `_messages` list is forwarded as conversation history, so the
  /// model retains memory of earlier turns within this sheet.
  Future<void> _send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _waitingForAi) return;

    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) {
      // Shouldn't happen — the FAB only renders when hasAiKey, but
      // defend anyway. Close the sheet rather than show a broken UI.
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _messages.add(ChatMessage(fromUser: true, text: text));
      _input.clear();
      _waitingForAi = true;
    });
    _scrollToBottom();

    final l10n = AppLocalizations.of(context)!;
    final ctxAsync = ref.read(tonightContextProvider);
    final ctx = ctxAsync.value;

    if (ctx == null || ctx.librarySample.isEmpty) {
      // Library hasn't loaded (provider error) or really is empty.
      // Show a helpful bubble instead of a hung spinner.
      setState(() {
        _messages.add(ChatMessage(
          fromUser: false,
          text: l10n.aiEmptyLibrary,
        ));
        _waitingForAi = false;
      });
      _scrollToBottom();
      return;
    }

    // Pre-search the library by the user's latest question so the
    // AI sees actual items even when they're not in the top-rated
    // sample. Without this, asking "en iyi Kore dizilerini listele"
    // returned "yok" because no Korean drama is in the rating-sorted
    // top-30 — even though the catalogue has 173 of them.
    final contentRepo = ref.read(contentRepositoryProvider);
    final queryMatches =
        await contentRepo.librarySearchByKeywords(text, limit: 60);
    final categoryOverview = await contentRepo.categoryOverview();

    final response = await gemini.recommendForTonight(
      conversation: _messages
          .map((m) => (fromUser: m.fromUser, text: m.text))
          .toList(),
      recentlyWatched: ctx.recentlyWatched,
      favorites: ctx.favorites,
      librarySample: ctx.librarySample,
      queryMatches: queryMatches,
      categoryOverview: categoryOverview,
    );

    if (!mounted) return;

    if (response == null || response.isEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          fromUser: false,
          text: l10n.aiError,
        ));
        _waitingForAi = false;
      });
    } else {
      setState(() {
        _messages.add(ChatMessage(
          fromUser: false,
          text: response.message.isNotEmpty
              ? response.message
              : (response.recommendations.isEmpty
                  ? l10n.aiNoMatches
                  : ''),
          recommendations: response.recommendations,
        ));
        _waitingForAi = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    // Defer to the next frame so the new bubble has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctxAsync = ref.watch(tonightContextProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textDisabledDark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                l10n.aiChatTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                color: AppColors.textSecondaryDark,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const Divider(height: 1),
          // Messages
          Expanded(
            child: ctxAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.aiError,
                    style:
                        TextStyle(color: AppColors.textSecondaryDark),
                  ),
                ),
              ),
              data: (_) => _messages.isEmpty
                  ? _buildEmptyState(l10n, isDark)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_waitingForAi ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _messages.length && _waitingForAi) {
                          return _ThinkingBubble(label: l10n.aiThinking);
                        }
                        return _MessageBubble(
                          message: _messages[i],
                          onPlay: _playRecommendation,
                          onOpenDetails: _openDetails,
                        );
                      },
                    ),
            ),
          ),
          // Input row
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    enabled: !_waitingForAi,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: l10n.aiChatInputHint,
                      filled: true,
                      fillColor: isDark
                          ? AppColors.backgroundDark
                          : AppColors.backgroundLight,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton.small(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  onPressed:
                      _waitingForAi ? null : () => _send(_input.text),
                  child: const Icon(Icons.send, size: 18),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, bool isDark) {
    final suggestions = [
      l10n.aiSuggestTonight,
      l10n.aiSuggestTogether,
      l10n.aiSuggestShort,
      l10n.aiSuggestKids,
      // Direct Q&A example so users notice the chat can also answer
      // "X hakkında bilgi ver" type queries — not just recommendation.
      l10n.aiSuggestAboutTitle,
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_awesome,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.aiChatGreeting,
                style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              OutlinedButton(
                onPressed: () => _send(s),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  s,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Look the recommendation's stream id up in the library snapshot
  /// and start the player. Falls back gracefully — if for some reason
  /// the id no longer exists (sync ran between snapshot and tap), do
  /// nothing. (UI never shows the option, so this is defensive.)
  Future<void> _playRecommendation(TonightRecommendation rec) async {
    final ch = _resolveChannel(rec);
    if (ch == null) return;
    final acc = ref.read(currentAccountProvider).value;
    if (acc == null) return;
    // M3U accounts store the stream URL on the channel row directly;
    // Xtream accounts build a URL from credentials. StreamUrlBuilder
    // handles both cases. We require an Xtream account to have
    // credentials for the latter path — if either is missing on an
    // Xtream row, bail.
    if (ch.streamUrl == null || ch.streamUrl!.isEmpty) {
      if (acc.username == null || acc.password == null) return;
    }
    final url = StreamUrlBuilder.build(
      acc.url,
      acc.username ?? '',
      acc.password ?? '',
      ch.streamId,
      ch.type,
      directUrl: ch.streamUrl,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    context.push('/player', extra: {
      'url': url,
      'title': ch.name,
      'type': _videoTypeFromString(ch.type),
      'logo': ch.streamIcon,
    });
  }

  /// Pop the sheet and surface the item via the pending-detail
  /// channel provider. Each section screen watches that provider and
  /// opens its own detail panel when a value is set — this is the
  /// same path the search results use, so behaviour stays consistent.
  void _openDetails(TonightRecommendation rec) {
    final ch = _resolveChannel(rec);
    if (ch == null) return;
    ref.read(pendingDetailChannelProvider.notifier).set(ch);
    Navigator.of(context).pop();
    switch (ch.type) {
      case 'movie':
        context.go('/movies');
      case 'series':
        context.go('/series');
      case 'live':
        context.go('/live');
      default:
        context.go('/dashboard');
    }
  }

  Channel? _resolveChannel(TonightRecommendation rec) {
    final ctx = ref.read(tonightContextProvider).value;
    if (ctx == null) return null;
    for (final pool in [ctx.librarySample, ctx.favorites, ctx.recentlyWatched]) {
      for (final ch in pool) {
        if (ch.streamId == rec.streamId) return ch;
      }
    }
    return null;
  }

  VideoType _videoTypeFromString(String type) {
    switch (type) {
      case 'movie':
        return VideoType.movie;
      case 'series':
        return VideoType.series;
      case 'live':
      default:
        return VideoType.live;
    }
  }
}

/// A single chat bubble. User messages are right-aligned and tinted
/// with the primary colour; AI messages are left-aligned, neutral,
/// and can carry inline [TonightRecommendation] cards.
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function(TonightRecommendation) onPlay;
  final void Function(TonightRecommendation) onOpenDetails;

  const _MessageBubble({
    required this.message,
    required this.onPlay,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fromUser = message.fromUser;
    final bg = fromUser
        ? AppColors.primary
        : (isDark ? AppColors.surfaceElevatedDark : Colors.white);
    final fg = fromUser
        ? Colors.white
        : (isDark ? AppColors.textDark : AppColors.textLight);

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(fromUser ? 16 : 4),
          bottomRight: Radius.circular(fromUser ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: TextStyle(color: fg, fontSize: 14, height: 1.4),
            ),
          if (message.recommendations.isNotEmpty) ...[
            if (message.text.isNotEmpty) const SizedBox(height: 10),
            for (final rec in message.recommendations)
              _RecCard(
                rec: rec,
                onPlay: onPlay,
                onOpenDetails: onOpenDetails,
              ),
          ],
        ],
      ),
    );

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

/// A recommendation card inside an AI bubble. Renders a small poster
/// (looked up from the library snapshot), title, AI reason, and play
/// + details actions.
class _RecCard extends ConsumerWidget {
  final TonightRecommendation rec;
  final Future<void> Function(TonightRecommendation) onPlay;
  final void Function(TonightRecommendation) onOpenDetails;

  const _RecCard({
    required this.rec,
    required this.onPlay,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = ref.watch(tonightContextProvider).value;
    if (ctx == null) return const SizedBox.shrink();
    Channel? ch;
    for (final pool in [ctx.librarySample, ctx.favorites, ctx.recentlyWatched]) {
      for (final c in pool) {
        if (c.streamId == rec.streamId) {
          ch = c;
          break;
        }
      }
      if (ch != null) break;
    }
    if (ch == null) {
      // Hallucinated id — drop the card. Logged through devtools
      // already via the service; no UI breadcrumb needed.
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ch.streamIcon != null && ch.streamIcon!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: ch.streamIcon!,
                  width: 56,
                  height: 84,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: 56,
                    height: 84,
                    color: AppColors.surfaceElevatedDark,
                    child: const Icon(Icons.movie_outlined,
                        color: AppColors.textTertiaryDark),
                  ),
                )
              : Container(
                  width: 56,
                  height: 84,
                  color: AppColors.surfaceElevatedDark,
                  child: const Icon(Icons.movie_outlined,
                      color: AppColors.textTertiaryDark),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ch.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ([
                  ch.year ?? '',
                  ch.genre ?? '',
                ].where((s) => s.isNotEmpty).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        ch.year ?? '',
                        ch.genre ?? '',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  rec.reason,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  FilledButton.icon(
                    onPressed: () => onPlay(rec),
                    icon: const Icon(Icons.play_arrow, size: 14),
                    label: Text(l10n.aiPlay),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => onOpenDetails(rec),
                    icon: const Icon(Icons.info_outline, size: 14),
                    label: Text(l10n.aiOpenDetails),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                ]),
              ]),
        ),
      ]),
    );
  }
}

/// "Thinking…" placeholder bubble shown while a Gemini call is in
/// flight. Same shape as an AI bubble so it doesn't visually jump
/// when the real response arrives and replaces it.
class _ThinkingBubble extends StatelessWidget {
  final String label;

  const _ThinkingBubble({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceElevatedDark : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: isDark ? AppColors.textDark : AppColors.textLight,
              fontSize: 13,
            ),
          ),
        ]),
      ),
    );
  }
}
