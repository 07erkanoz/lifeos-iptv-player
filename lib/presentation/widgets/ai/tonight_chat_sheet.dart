import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/tonight_recommendation.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'dart:convert';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/favorites_repository.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/data/repositories/taste_profile_repository.dart';
import 'package:lifeostv/data/services/semantic_search_service.dart';
import 'package:lifeostv/data/services/notification_service.dart';
import 'package:lifeostv/data/services/ai_instrumentation_service.dart';
import 'package:lifeostv/data/services/voice_chat_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/data/services/ai_model_policy.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/widgets/ai/ai_feedback_sheet.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/state/tonight_context_provider.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/data/services/playback_url_resolver.dart';

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

/// Chat history Notifier — survives modal open/close so the user
/// can dismiss the sheet, navigate around the app, and come back
/// to a still-populated conversation. Cleared explicitly via the
/// trash button in the header, or implicitly on app restart.
class _ChatHistoryNotifier extends Notifier<List<ChatMessage>> {
  @override
  List<ChatMessage> build() => const [];

  void add(ChatMessage message) {
    state = [...state, message];
  }

  void clear() {
    state = const [];
  }
}

final tonightChatHistoryProvider =
    NotifierProvider<_ChatHistoryNotifier, List<ChatMessage>>(
  _ChatHistoryNotifier.new,
);

/// Active spoiler-protection context for the chat. When set, every
/// chat call to Gemini carries a `currentEpisode` field that tells
/// the AI to discuss the named series only up to the given episode
/// and never reveal what happens later.
///
/// Set explicitly by the user via the shield button in the chat
/// header (which opens a picker fed by their continue-watching
/// list). Stays put across send turns so the user doesn't have to
/// re-arm it for every question.
class ChatEpisodeContext {
  final int streamId; // parent series id
  final String title;
  final int season;
  final int episode;

  const ChatEpisodeContext({
    required this.streamId,
    required this.title,
    required this.season,
    required this.episode,
  });

  String get epLabel => 'S${season}E$episode';

  Map<String, dynamic> toPromptJson() => {
        'title': title,
        'season': season,
        'episode': episode,
        'epLabel': epLabel,
      };
}

class _ChatEpisodeContextNotifier extends Notifier<ChatEpisodeContext?> {
  @override
  ChatEpisodeContext? build() => null;

  void set(ChatEpisodeContext? value) => state = value;
  void clear() => state = null;
}

final chatEpisodeContextProvider =
    NotifierProvider<_ChatEpisodeContextNotifier, ChatEpisodeContext?>(
  _ChatEpisodeContextNotifier.new,
);

class _TonightChatSheetState extends ConsumerState<TonightChatSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _waitingForAi = false;

  /// Navigation an agent tool requested (play / open detail). Deferred
  /// until the agent loop finishes — running it mid-loop would pop the
  /// sheet and unmount us while we're still awaiting Gemini.
  Future<void> Function()? _pendingAgentNav;

  /// Read the persisted chat history. Backed by Riverpod so the list
  /// survives the modal closing — we used to keep it in a local
  /// `_messages` field that got wiped every time the user dismissed
  /// the sheet.
  List<ChatMessage> get _messages => ref.read(tonightChatHistoryProvider);

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

    ref.read(tonightChatHistoryProvider.notifier).add(
          ChatMessage(fromUser: true, text: text),
        );
    setState(() {
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
      ref.read(tonightChatHistoryProvider.notifier).add(
            ChatMessage(fromUser: false, text: l10n.aiEmptyLibrary),
          );
      setState(() => _waitingForAi = false);
      _scrollToBottom();
      return;
    }

    // Pre-search the library by the user's latest question so the
    // AI sees actual items even when they're not in the top-rated
    // sample. Without this, asking "en iyi Kore dizilerini listele"
    // returned "yok" because no Korean drama is in the rating-sorted
    // top-30 — even though the catalogue has 173 of them.
    final contentRepo = ref.read(contentRepositoryProvider);
    // Pull a generous slice — when the user says "tümünü listele"
    // the AI may want to surface 10+ items, and we want it to have
    // room to pick the best ones from a wider pool rather than be
    // capped at 60. Cost is ~50 ms of bounded DB scan.
    final queryMatches =
        await contentRepo.librarySearchByKeywords(text, limit: 120);
    final categoryOverview = await contentRepo.categoryOverview();
    // Shared weighted taste profile. Hands the chat the same
    // aggregate view the dashboard rails use so the AI can break
    // ties between equally-plausible candidates by reading the
    // actual scores instead of re-deriving them from raw lists.
    final tasteProfile =
        await ref.read(tasteProfileProvider.future);

    // Wrap the AI call with the instrumentation service so the
    // Settings → Debug panel can show latency / success / timeout
    // metrics. Telemetry write is fire-and-forget — the actual
    // user-facing response shape is unchanged.
    final instrumentation = ref.read(aiInstrumentationProvider);
    var response = await instrumentation.record<TonightResponse>(
      feature: 'chat',
      model: AiModelPolicy.chat,
      candidateCount: queryMatches.length + ctx.librarySample.length,
      outputCountOf: (r) => r.recommendations.length,
      // The agent can make several round-trips (search → act → present),
      // so give it more headroom than the single-shot path used.
      timeout: const Duration(seconds: 60),
      run: () {
        final lang = ref.read(settingsProvider).language.name == 'system'
            ? 'tr'
            : ref.read(settingsProvider).language.name;
        final episodeCtx = ref.read(chatEpisodeContextProvider);
        // Compact context blob the agent sees on turn 1. The model can
        // also call searchLibrary to pull in anything beyond this slice.
        Map<String, dynamic> compact(Channel c) => {
              'streamId': c.streamId,
              'title': c.name,
              'type': c.type,
              if (c.genre != null && c.genre!.isNotEmpty) 'genre': c.genre,
              if (c.year != null && c.year!.isNotEmpty) 'year': c.year,
            };
        final now = DateTime.now();
        final contextBlob = <String, dynamic>{
          // So the agent can compute epochMs for relative reminders
          // ("Cuma 21:00", "2 saat sonra").
          'nowEpochMs': now.millisecondsSinceEpoch,
          'nowLocal': now.toIso8601String(),
          'recentlyWatched': ctx.recentlyWatched.map(compact).toList(),
          'favorites': ctx.favorites.map(compact).toList(),
          'queryMatches': queryMatches.map(compact).toList(),
          'library': ctx.librarySample.map(compact).toList(),
          if (ctx.recentAdditions.isNotEmpty)
            'recentAdditions': ctx.recentAdditions.map(compact).toList(),
          if (categoryOverview.isNotEmpty) 'categories': categoryOverview,
          if (tasteProfile.toPromptJson().isNotEmpty)
            'tasteProfile': tasteProfile.toPromptJson(),
          if (episodeCtx != null) 'currentEpisode': episodeCtx.toPromptJson(),
        };
        return gemini.runAgent(
          conversation: _messages
              .map((m) => (fromUser: m.fromUser, text: m.text))
              .toList(),
          contextJson: jsonEncode(contextBlob),
          targetLanguage: lang,
          onToolCall: _agentToolCall,
        );
      },
    );

    // Resilience: if the agent path failed (transport / tool error),
    // fall back to the plain recommendation call so the chat still
    // answers instead of showing "couldn't reach the assistant".
    if (response == null) {
      final lang = ref.read(settingsProvider).language.name == 'system'
          ? 'tr'
          : ref.read(settingsProvider).language.name;
      response = await gemini.recommendForTonight(
        conversation: _messages
            .map((m) => (fromUser: m.fromUser, text: m.text))
            .toList(),
        recentlyWatched: ctx.recentlyWatched,
        favorites: ctx.favorites,
        librarySample: ctx.librarySample,
        queryMatches: queryMatches,
        recentAdditions: ctx.recentAdditions,
        categoryOverview: categoryOverview,
        targetLanguage: lang,
        tasteProfile: tasteProfile.toPromptJson(),
        currentEpisode: ref.read(chatEpisodeContextProvider)?.toPromptJson(),
      );
    }

    if (!mounted) return;

    if (response == null || response.isEmpty) {
      ref.read(tonightChatHistoryProvider.notifier).add(
            ChatMessage(fromUser: false, text: l10n.aiError),
          );
      setState(() => _waitingForAi = false);
    } else {
      // Resolve every recommended streamId from the DB directly so
      // the rec card renders no matter where the id came from
      // (queryMatches / library / recently watched / favourites).
      // Without this, AI picks from queryMatches were dropped as
      // "hallucinated" because the card widget only searched the
      // standard pools.
      final db = ref.read(appDatabaseProvider);
      final ids = response.recommendations
          .map((r) => r.streamId)
          .toSet()
          .toList();
      final resolved = <int, Channel>{};
      if (ids.isNotEmpty) {
        final rows = await (db.select(db.channels)
              ..where((t) => t.streamId.isIn(ids)))
            .get();
        for (final c in rows) {
          // Composite primary key (streamId, type) — keep the first
          // we see; subsequent collisions across types are rare and
          // the chat doesn't disambiguate them anyway.
          resolved.putIfAbsent(c.streamId, () => c);
        }
      }
      if (!mounted) return;
      ref.read(tonightChatHistoryProvider.notifier).add(
            ChatMessage(
              fromUser: false,
              text: response.message.isNotEmpty
                  ? response.message
                  : (response.recommendations.isEmpty
                      ? l10n.aiNoMatches
                      : ''),
              recommendations: response.recommendations,
              resolvedChannels: resolved,
              followUps: response.followUps,
            ),
          );
      setState(() => _waitingForAi = false);
    }
    _scrollToBottom();
    // An agent tool asked us to play / open something — do it now that
    // the loop is done and the message is on screen.
    final nav = _pendingAgentNav;
    _pendingAgentNav = null;
    if (nav != null) await nav();
  }

  /// Executes one agent tool call against the app. Read tools return
  /// data; favourite/profile run immediately; play/openDetail are
  /// deferred (they pop the sheet) into [_pendingAgentNav].
  Future<Map<String, dynamic>> _agentToolCall(
      String name, Map<String, dynamic> args) async {
    final db = ref.read(appDatabaseProvider);
    Future<Channel?> resolve(int id) async {
      final rows = await (db.select(db.channels)
            ..where((t) => t.streamId.equals(id)))
          .get();
      return rows.isEmpty ? null : rows.first;
    }

    switch (name) {
      case 'searchLibrary':
        final q = (args['query'] ?? '').toString();
        final type = args['type']?.toString();
        final hits = await ref
            .read(semanticSearchServiceProvider)
            .search(q, k: 20, restrictType: type);
        var channels = <Channel>[];
        if (hits.isNotEmpty) {
          final ids = hits.map((h) => h.streamId).toList();
          final rows = await (db.select(db.channels)
                ..where((t) => t.streamId.isIn(ids)))
              .get();
          final byId = {for (final r in rows) r.streamId: r};
          channels = [
            for (final h in hits)
              if (byId[h.streamId] != null) byId[h.streamId]!
          ];
        }
        // Fall back to keyword search when nothing's embedded yet.
        if (channels.isEmpty) {
          channels = await ref
              .read(contentRepositoryProvider)
              .searchChannels(q, limit: 20);
          if (type != null) {
            channels = channels.where((c) => c.type == type).toList();
          }
        }
        return {
          'results': [
            for (final c in channels.take(20))
              {
                'streamId': c.streamId,
                'title': c.name,
                'type': c.type,
                if (c.genre != null) 'genre': c.genre,
                if (c.year != null) 'year': c.year,
              }
          ],
        };

      case 'searchLiveChannels':
        final q = (args['query'] ?? '').toString();
        final chans = await ref
            .read(contentRepositoryProvider)
            .searchLiveChannels(q, limit: 20);
        return {
          'results': [
            for (final c in chans)
              {'streamId': c.streamId, 'title': c.name, 'type': 'live'}
          ],
        };

      case 'getLiveNowOnAir':
        final rows =
            await ref.read(contentRepositoryProvider).liveNowOnAir(limit: 30);
        return {
          'results': [
            for (final r in rows)
              {
                'streamId': r.channel.streamId,
                'channel': r.channel.name,
                'now': r.program.title,
                'startEpochMs': r.program.start.millisecondsSinceEpoch,
                'stopEpochMs': r.program.stop.millisecondsSinceEpoch,
              }
          ],
        };

      case 'findPrograms':
        final q = (args['query'] ?? '').toString();
        final rows = await ref
            .read(contentRepositoryProvider)
            .searchUpcomingPrograms(q, limit: 20);
        return {
          'results': [
            for (final r in rows)
              {
                'streamId': r.channel.streamId,
                'channel': r.channel.name,
                'title': r.program.title,
                'startEpochMs': r.program.start.millisecondsSinceEpoch,
                'stopEpochMs': r.program.stop.millisecondsSinceEpoch,
              }
          ],
        };

      case 'addFavorite':
        final id = (args['streamId'] as num?)?.toInt();
        final type = args['type']?.toString();
        if (id == null || type == null) return {'ok': false};
        final ch = await resolve(id);
        await ref.read(favoritesRepositoryProvider).addFavorite(
            id, type, ch?.name ?? '', ch?.streamIcon);
        return {'ok': true, 'title': ch?.name};

      case 'removeFavorite':
        final id = (args['streamId'] as num?)?.toInt();
        final type = args['type']?.toString();
        if (id == null || type == null) return {'ok': false};
        await ref.read(favoritesRepositoryProvider).removeFavorite(id, type);
        return {'ok': true};

      case 'switchProfile':
        final wanted = (args['name'] ?? '').toString().toLowerCase().trim();
        final repo = await ref.read(profileRepositoryProvider.future);
        final all = await repo.getAll();
        final match = all.where((p) => p.name.toLowerCase() == wanted).toList();
        if (match.isEmpty) {
          return {
            'ok': false,
            'available': all.map((p) => p.name).toList(),
          };
        }
        await repo.setActiveProfile(match.first.id);
        ref.invalidate(activeProfileIdProvider);
        return {'ok': true};

      case 'playContent':
        final id = (args['streamId'] as num?)?.toInt();
        if (id == null) return {'ok': false};
        final ch = await resolve(id);
        if (ch == null) return {'ok': false, 'error': 'not found'};
        _pendingAgentNav = () => _playChannel(ch);
        return {'ok': true, 'title': ch.name};

      case 'openDetail':
        final id = (args['streamId'] as num?)?.toInt();
        if (id == null) return {'ok': false};
        final ch = await resolve(id);
        if (ch == null) return {'ok': false, 'error': 'not found'};
        _pendingAgentNav = () => _openDetailChannel(ch);
        return {'ok': true, 'title': ch.name};

      case 'setReminder':
        final title = (args['title'] ?? '').toString();
        final epoch = (args['epochMs'] as num?)?.toInt();
        if (title.isEmpty || epoch == null) return {'ok': false};
        final l10n = AppLocalizations.of(context)!;
        final ok = await ref.read(notificationServiceProvider).scheduleReminder(
              id: (epoch ~/ 1000),
              title: title,
              body: l10n.reminderBody,
              whenEpochMs: epoch,
            );
        return {'ok': ok};

      default:
        return {'error': 'unknown tool'};
    }
  }

  bool _openingPlayback = false;

  Future<void> _playChannel(Channel ch) async {
    if (_openingPlayback) return;
    final acc = ref.read(currentAccountProvider).value;
    if (acc == null) return;
    _openingPlayback = true;
    try {
      final url = await ref.read(playbackUrlResolverProvider).resolve(acc, ch);
      if (!mounted || ref.read(currentAccountProvider).value?.id != acc.id) return;
      if (!mounted) return;
      Navigator.of(context).pop();
      context.push('/player', extra: {
        'url': url,
        'streamId': ch.streamId,
        'accountId': ch.accountId,
        'title': ch.name,
        'type': _videoTypeFromString(ch.type),
        'logo': ch.streamIcon,
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.streamLoadFailed)),
      );
    } finally {
      _openingPlayback = false;
    }
  }

  Future<void> _openDetailChannel(Channel ch) async {
    ref.read(pendingDetailChannelProvider.notifier).set(ch);
    if (!mounted) return;
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

  /// Open the spoiler-shield picker. Lists every series the user is
  /// currently mid-watch on (joined from PlaybackProgress + Channels
  /// + history's last-touched series ids) plus an "Off" tile to
  /// clear protection. Tapping a series sets the chat's
  /// chatEpisodeContextProvider with that series + last-watched
  /// episode pair, so subsequent /send calls carry spoiler-safe
  /// hints.
  ///
  /// We intentionally don't ask the user for a season/episode by
  /// hand — too friction-heavy. We use whatever the user has played
  /// most recently for that series. If they want a different cap,
  /// they can play the desired episode briefly and re-open the
  /// picker.
  Future<void> _showSpoilerShieldPicker(BuildContext context) async {
    final db = ref.read(appDatabaseProvider);
    final l10n = AppLocalizations.of(context)!;
    final current = ref.read(chatEpisodeContextProvider);

    // Pull series episodes the user has touched, joined with their
    // parent series so we can show the parent title. We assume the
    // series episode is a Channel of type='series' whose
    // categoryId / parent we resolve via the existing series_screen
    // pattern — for now, surface the in-history series channels
    // directly (the row is keyed by the *parent* series id when
    // `_lastEpisodeProgress` is computed there). For the chat
    // picker we just need title + a default S/E pair, so we read
    // the latest playback row per series.
    final rows = await (db.select(db.channels).join([
      db.accountInnerJoin(
        db.playbackProgress,
        db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
            db.playbackProgress.type.equalsExp(db.channels.type),
      ),
    ])
          ..where(db.channels.type.equals('series'))
          ..orderBy([
            OrderingTerm(
                expression: db.playbackProgress.updatedAt,
                mode: OrderingMode.desc),
          ])
          ..limit(20))
        .get();

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shield_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.aiSpoilerShieldTitle,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                l10n.aiSpoilerShieldDesc,
                style: const TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              // "Off" tile
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.do_not_disturb_off,
                    color: AppColors.textSecondaryDark),
                title: Text(l10n.aiSpoilerShieldOff,
                    style:
                        const TextStyle(color: AppColors.textDark)),
                trailing: current == null
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  ref
                      .read(chatEpisodeContextProvider.notifier)
                      .clear();
                  Navigator.of(sheetCtx).pop();
                },
              ),
              if (rows.isNotEmpty) const Divider(),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.aiSpoilerShieldEmpty,
                    style: const TextStyle(
                      color: AppColors.textTertiaryDark,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final ch = rows[i].readTable(db.channels);
                      // We don't have season/episode metadata on
                      // the row directly. Default to S1E1 as a
                      // safe lower bound — the user can adjust
                      // by playing the episode they want, then
                      // reopening this picker. In practice the
                      // *parent series* level cap is what matters
                      // for spoiler safety anyway.
                      final isSelected = current?.streamId == ch.streamId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shield,
                            color: AppColors.primary),
                        title: Text(
                          ch.name,
                          style: const TextStyle(
                              color: AppColors.textDark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: isSelected && current != null
                            ? Text(
                                '${l10n.aiSpoilerShieldUpTo} ${current.epLabel}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                ),
                              )
                            : null,
                        trailing: isSelected
                            ? const Icon(Icons.check,
                                color: AppColors.primary)
                            : null,
                        onTap: () {
                          ref
                              .read(chatEpisodeContextProvider.notifier)
                              .set(ChatEpisodeContext(
                                streamId: ch.streamId,
                                title: ch.name,
                                // We don't yet derive S/E from the
                                // touched row. Reasonable default
                                // until we wire the per-series last-
                                // episode lookup here too:
                                season: current?.streamId == ch.streamId
                                    ? current!.season
                                    : 1,
                                episode:
                                    current?.streamId == ch.streamId
                                        ? current!.episode
                                        : 1,
                              ));
                          Navigator.of(sheetCtx).pop();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
    // ref.watch the chat-history provider so this widget rebuilds
    // when add()/clear() fires elsewhere (e.g. mid-stream while we
    // _send and the modal is technically still showing the old list).
    final messages = ref.watch(tonightChatHistoryProvider);

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
              // Spoiler-shield toggle. When active, the chip shows
              // the current "S1E10" cap so the user knows what
              // they're protected from being spoiled about. Tap to
              // change or clear via _showSpoilerShieldPicker.
              _SpoilerShieldBadge(
                onTap: () => _showSpoilerShieldPicker(context),
              ),
              const SizedBox(width: 4),
              if (messages.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.textSecondaryDark,
                  tooltip: l10n.aiChatClear,
                  onPressed: _waitingForAi
                      ? null
                      : () => ref
                          .read(tonightChatHistoryProvider.notifier)
                          .clear(),
                ),
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
              data: (_) => messages.isEmpty
                  ? _buildEmptyState(l10n, isDark)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length + (_waitingForAi ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == messages.length && _waitingForAi) {
                          return _ThinkingBubble(label: l10n.aiThinking);
                        }
                        return _MessageBubble(
                          message: messages[i],
                          onPlay: _playRecommendation,
                          onOpenDetails: _openDetails,
                          onFollowUp: _send,
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
                // Voice input button — only rendered on mobile
                // (Android / iOS). Desktop and TV builds load the
                // VoiceChatService but it short-circuits to
                // isSupported=false, hiding this button.
                if (PlatformHelper.isMobile) ...[
                  _VoiceInputButton(
                    enabled: !_waitingForAi,
                    onPartial: (text) {
                      // Show interim transcription as the user
                      // speaks — same UX as Gboard / Google
                      // Keyboard's microphone overlay.
                      setState(() {
                        _input.text = text;
                        _input.selection = TextSelection.collapsed(
                            offset: text.length);
                      });
                    },
                    onFinal: (text) {
                      // Auto-send on STT completion. The transcript
                      // is committed text — kullanıcı düzeltmek
                      // isterse zaten ses tanıma kaba olduğunda
                      // tekrar dener; otomatik göndermek voice
                      // chat'in tüm noktasını kazanır.
                      final t = text.trim();
                      if (t.isEmpty) return;
                      _input.text = t;
                      _send(t);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
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
                  // Explicit heroTag — voice mic FAB shares the row
                  // and already declares 'voice-input-fab'. Without
                  // a unique tag here Flutter raises a hero conflict
                  // assertion when both render simultaneously.
                  heroTag: 'chat-send-fab',
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
    final ch = await _resolveChannel(rec);
    if (ch == null || !mounted) return;
    await _playChannel(ch);
  }

  /// Pop the sheet and surface the item via the pending-detail
  /// channel provider. Each section screen watches that provider and
  /// opens its own detail panel when a value is set — this is the
  /// same path the search results use, so behaviour stays consistent.
  Future<void> _openDetails(TonightRecommendation rec) async {
    final ch = await _resolveChannel(rec);
    if (ch == null) return;
    ref.read(pendingDetailChannelProvider.notifier).set(ch);
    if (!mounted) return;
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

  /// Resolve a rec's streamId to a Channel for play / details
  /// routing.
  ///
  /// First sweeps the message-local `resolvedChannels` maps — these
  /// were populated by the DB lookup we run right after the AI
  /// response lands, so they always contain the items the AI just
  /// recommended regardless of which pool they came from (queryMatches
  /// / library / favourites / history).
  ///
  /// Falls back to a direct DB query as a last resort so play and
  /// details survive even on legacy message objects that didn't get
  /// the resolved map populated.
  Future<Channel?> _resolveChannel(TonightRecommendation rec) async {
    // 1. Check the resolved map on every AI message in the session —
    //    walk newest first so the latest answer wins on duplicates.
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.fromUser) continue;
      final ch = m.resolvedChannels[rec.streamId];
      if (ch is Channel) return ch;
    }
    // 2. Legacy in-memory context pools (kept for safety).
    final ctx = ref.read(tonightContextProvider).value;
    if (ctx != null) {
      for (final pool in [
        ctx.librarySample,
        ctx.favorites,
        ctx.recentlyWatched,
      ]) {
        for (final ch in pool) {
          if (ch.streamId == rec.streamId) return ch;
        }
      }
    }
    // 3. Direct DB lookup — last-resort safety net. ~5 ms on this
    //    catalogue, dwarfed by the navigation transition anyway.
    final db = ref.read(appDatabaseProvider);
    final row = await (db.select(db.channels)
          ..where((t) => t.streamId.equals(rec.streamId))
          ..limit(1))
        .getSingleOrNull();
    return row;
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
  final void Function(String)? onFollowUp;

  const _MessageBubble({
    required this.message,
    required this.onPlay,
    required this.onOpenDetails,
    this.onFollowUp,
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
                resolved: message.resolvedChannels[rec.streamId],
                onPlay: onPlay,
                onOpenDetails: onOpenDetails,
              ),
          ],
          // Follow-up suggestion chips — AI proposes 3-4 directions
          // the conversation could plausibly go next. Tapping a chip
          // submits it as the next user turn, no typing needed.
          // Only rendered on AI bubbles that supplied followUps; user
          // bubbles get nothing here.
          if (!fromUser && message.followUps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in message.followUps)
                  _FollowUpChip(
                    label: chip,
                    onTap: () => onFollowUp?.call(chip),
                  ),
              ],
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

  /// Pre-resolved Channel for this rec's streamId. Sourced from the
  /// DB lookup the chat sheet does right after the AI response lands,
  /// so the card always renders regardless of whether the id was in
  /// queryMatches, library, recently-watched or favourites.
  final Channel? resolved;

  final Future<void> Function(TonightRecommendation) onPlay;
  final void Function(TonightRecommendation) onOpenDetails;

  const _RecCard({
    required this.rec,
    required this.resolved,
    required this.onPlay,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Prefer the DB-resolved channel passed in from the parent.
    // Fall back to the context pools for backward compatibility, in
    // case any code path still constructs a ChatMessage without
    // populating resolvedChannels.
    Channel? ch = resolved;
    if (ch == null) {
      final ctx = ref.watch(tonightContextProvider).value;
      if (ctx == null) return const SizedBox.shrink();
      for (final pool in [
        ctx.librarySample,
        ctx.favorites,
        ctx.recentlyWatched,
      ]) {
        for (final c in pool) {
          if (c.streamId == rec.streamId) {
            ch = c;
            break;
          }
        }
        if (ch != null) break;
      }
    }
    if (ch == null) {
      // Genuine hallucination — id doesn't exist in the DB at all.
      return const SizedBox.shrink();
    }
    // Pin to a non-nullable local so closures (onPressed below)
    // don't trip the analyzer with promotion-across-closure errors.
    final channel = ch;

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
                  memCacheWidth: 168,
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
                Row(children: [
                  Expanded(
                    child: Text(
                      ch.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Feedback overflow menu — Sevmedim / Bunun gibi
                  // daha / Neden önerildi?. Discoverable, low-noise,
                  // sits inside the card's white-on-dark text region.
                  IconButton(
                    icon: const Icon(Icons.more_horiz,
                        color: Colors.white70, size: 18),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    tooltip: AppLocalizations.of(context)!.aiFeedbackWhy,
                    onPressed: () => AiFeedbackSheet.show(
                      context,
                      streamId: channel.streamId,
                      type: channel.type,
                      title: channel.name,
                      reason: rec.reason,
                      feature: 'chat',
                    ),
                  ),
                ]),
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

/// Follow-up suggestion chip rendered under an AI bubble. Tapping
/// fires the chip's text back as the next user turn — the user
/// doesn't have to retype anything to drill deeper into the
/// conversation. AI generates 3-4 of these per response.
class _FollowUpChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _FollowUpChip({required this.label, required this.onTap});

  @override
  State<_FollowUpChip> createState() => _FollowUpChipState();
}

class _FollowUpChipState extends State<_FollowUpChip> {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.22)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.4),
                width: _focused ? 1.5 : 1.0,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chevron_right,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Header badge that surfaces the current spoiler-shield state.
/// Shows a plain outlined shield icon when off, and a filled
/// shield + "SXEY" chip when armed. Tap (or D-pad select) opens
/// the picker via the caller-supplied [onTap].
class _SpoilerShieldBadge extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _SpoilerShieldBadge({required this.onTap});

  @override
  ConsumerState<_SpoilerShieldBadge> createState() =>
      _SpoilerShieldBadgeState();
}

class _SpoilerShieldBadgeState
    extends ConsumerState<_SpoilerShieldBadge> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Defensive double-gate: chat sheet itself is opened by an
    // AI-gated FAB, but if some future caller reaches the chat
    // surface without a key, this badge must not render.
    final hasAiKey = ref.watch(settingsProvider).hasAiKey;
    if (!hasAiKey) return const SizedBox.shrink();

    final ctx = ref.watch(chatEpisodeContextProvider);
    final active = ctx != null;
    return Focus(
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
      child: Tooltip(
        message: AppLocalizations.of(context)!.aiSpoilerShieldTitle,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? AppColors.primary
                    : (active
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : Colors.transparent),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? Icons.shield : Icons.shield_outlined,
                  color: active
                      ? AppColors.primary
                      : AppColors.textSecondaryDark,
                  size: 18,
                ),
                if (active) ...[
                  const SizedBox(width: 5),
                  Text(
                    ctx.epLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
}

/// Mic button at the left of the chat input row. Toggles between
/// idle and listening states; the listening state pulses with a
/// red glow so the user has clear feedback that the recogniser is
/// hot. On Android 6+ the runtime RECORD_AUDIO permission gets
/// requested on the first tap (handled inside speech_to_text).
///
/// Streams partial transcripts through [onPartial] so the text
/// field can update live as the user speaks. The final transcript
/// fires through [onFinal] when the recogniser commits (after a
/// 3-second pause of silence or when the user taps to stop).
class _VoiceInputButton extends ConsumerStatefulWidget {
  final bool enabled;
  final void Function(String partial) onPartial;
  final void Function(String finalText) onFinal;

  const _VoiceInputButton({
    required this.enabled,
    required this.onPartial,
    required this.onFinal,
  });

  @override
  ConsumerState<_VoiceInputButton> createState() =>
      _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<_VoiceInputButton>
    with SingleTickerProviderStateMixin {
  bool _listening = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Warm up the engine asynchronously so the first tap doesn't
    // have an extra 200-400 ms init latency on top of mic
    // permission round-trip. Fire-and-forget — failures just mean
    // isSupported stays false and the button hides itself.
    Future.microtask(() async {
      await ref.read(voiceChatServiceProvider).ensureInitialised();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    // Best-effort: if the user closes the sheet mid-dictation,
    // tear the listener down so the mic light doesn't stay on.
    ref.read(voiceChatServiceProvider).stopListening();
    super.dispose();
  }

  Future<void> _toggle() async {
    final svc = ref.read(voiceChatServiceProvider);
    if (_listening) {
      await svc.stopListening();
      if (mounted) {
        setState(() => _listening = false);
        _pulseCtrl.stop();
      }
      return;
    }
    final lang = ref.read(settingsProvider).language;
    final localeId =
        lang == AppLanguage.system ? null : _mapLanguageToLocale(lang);
    final ok = await svc.startListening(
      localeId: localeId,
      onPartial: widget.onPartial,
      onFinal: (text) {
        if (!mounted) return;
        setState(() => _listening = false);
        _pulseCtrl.stop();
        widget.onFinal(text);
      },
    );
    if (!mounted) return;
    if (!ok) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.voiceUnavailable)),
      );
      return;
    }
    setState(() => _listening = true);
    _pulseCtrl.repeat(reverse: true);
  }

  String? _mapLanguageToLocale(AppLanguage lang) {
    // BCP-47 tags the SpeechRecognizer engine expects. Missing
    // locales degrade to the device default (Android's recogniser
    // falls back gracefully) — important for Kurdish, where
    // SpeechRecognizer support is patchy.
    switch (lang.name) {
      case 'tr':
        return 'tr_TR';
      case 'en':
        return 'en_US';
      case 'de':
        return 'de_DE';
      case 'fr':
        return 'fr_FR';
      case 'es':
        return 'es_ES';
      case 'ar':
        return 'ar_SA';
      case 'ru':
        return 'ru_RU';
      case 'ku':
        // Most Android SpeechRecognizer engines don't ship Kurdish;
        // fall back to Turkish — closest match for Kurmancî
        // speakers using tr-TR keyboards on Turkish devices.
        return 'tr_TR';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(voiceChatServiceProvider);
    if (!svc.isSupported) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, _) {
        final glow = 0.5 + 0.5 * _pulseCtrl.value;
        return FloatingActionButton.small(
          heroTag: 'voice-input-fab',
          backgroundColor: _listening
              ? Colors.red.withValues(alpha: glow)
              : AppColors.surfaceElevatedDark,
          foregroundColor:
              _listening ? Colors.white : AppColors.primary,
          elevation: _listening ? 4 : 0,
          onPressed: widget.enabled ? _toggle : null,
          child: Icon(
            _listening ? Icons.stop_circle : Icons.mic_none,
            size: 18,
          ),
        );
      },
    );
  }
}
