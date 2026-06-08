import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/ai_model_policy.dart';
import 'package:lifeostv/data/models/search_intent.dart';
import 'package:lifeostv/data/models/similar_group.dart';
import 'package:lifeostv/data/models/tonight_recommendation.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Thin Gemini REST client. Only what LifeOs TV actually calls —
/// no Google SDK dependency, no model abstraction layer.
///
/// Construct with the user's API key (read from settings). Every
/// method returns `null` on any failure (network / timeout / quota /
/// malformed response) instead of throwing — the calling UI layer
/// always has a graceful fallback (plain SQL search, etc.) and we
/// don't want a flaky Gemini call to break the search box.
class GeminiService {
  /// `gemini-2.5-flash` because:
  ///   * cheap on the free tier (1500 RPD as of 2026-05)
  ///   * fast enough to keep search-as-you-type tolerable
  ///   * structured-output-capable via `responseSchema`
  static const _model = 'gemini-2.5-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String _apiKey;
  final Dio _dio;

  GeminiService(this._apiKey)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true, // we surface non-200 ourselves
        ));

  /// Parse a natural-language query like "kısa süreli polis filmi"
  /// into a [SearchIntent] using Gemini structured output.
  ///
  /// Returns `null` when Gemini is unreachable, returns a non-200,
  /// or returns text that doesn't fit the JSON schema. Callers fall
  /// back to plain keyword search in that case.
  ///
  /// `responseSchema` + `responseMimeType:application/json` *should*
  /// force valid JSON, but Gemini occasionally adds stray prose
  /// around it (especially for Turkish prompts); we tolerate that
  /// by locating the outermost `{...}` instead of strict-parsing
  /// the whole body.
  Future<SearchIntent?> parseSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty || _apiKey.isEmpty) return null;

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': _systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': q},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _responseSchema,
            'temperature': 0.0, // deterministic for the same query
            'maxOutputTokens': 256,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] parseSearchQuery status=${res.statusCode} body=${res.data}');
        return null;
      }

      final body = res.data;
      if (body is! Map<String, dynamic>) return null;

      // Structured-output payload sits in
      // `candidates[0].content.parts[0].text` as a JSON string.
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      // Tolerate stray prefix/suffix prose — find the outermost
      // JSON object and parse just that.
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = text.substring(start, end + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] JSON decode failed: $e   raw=$jsonStr');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;

      return SearchIntent.fromJson(decoded);
    } catch (e) {
      debugPrint('[Gemini] parseSearchQuery failed: $e');
      return null;
    }
  }

  /// Ask Gemini for a "what should I watch tonight?" recommendation.
  ///
  /// Multi-turn — the [conversation] list carries every prior user
  /// turn and AI reply so follow-ups ("daha kısa bir şey", "drama
  /// dışında") stay in context. We send the [recentlyWatched] /
  /// [favorites] / [librarySample] arrays alongside so the model
  /// only recommends real IDs the user can actually play.
  ///
  /// Returns `null` on any failure (same contract as
  /// [parseSearchQuery]) so the chat UI can show a friendly error
  /// bubble instead of crashing.
  ///
  /// Cost budget: each call serialises ~50 channels of metadata
  /// (titles, genres, years, ratings) plus the conversation —
  /// roughly 5-8 KB / 1.5-2.5K input tokens. Well inside Gemini
  /// 2.5 Flash's free-tier daily allowance for personal use.
  Future<TonightResponse?> recommendForTonight({
    required List<({bool fromUser, String text})> conversation,
    required List<Channel> recentlyWatched,
    required List<Channel> favorites,
    required List<Channel> librarySample,
    List<Channel> queryMatches = const [],
    List<Channel> recentAdditions = const [],
    List<Map<String, dynamic>> categoryOverview = const [],
    String targetLanguage = 'tr',
    Map<String, dynamic> tasteProfile = const {},
    /// Optional "user is currently watching X" hint. When set, the
    /// system prompt switches to spoiler-aware mode: the AI can
    /// discuss the show up to and including the given episode, but
    /// must NOT reveal anything that happens beyond it.
    ///
    /// Shape: `{"title": str, "season": int, "episode": int,
    ///          "epLabel": "S1E5"}`. Optional fields tolerated —
    /// the prompt only depends on title + epLabel being present.
    Map<String, dynamic>? currentEpisode,
  }) async {
    if (_apiKey.isEmpty || conversation.isEmpty) return null;

    try {
      // Compact each channel into the smallest informative form the
      // model needs. Skipping `plot` keeps the prompt small; the AI
      // gets to pick from the sample by id and the UI looks up the
      // full row to render. We *do* keep genre/year/rating because
      // they're the levers the AI needs to reason about fit.
      // Use `streamId` as the key so it matches the output schema —
      // previously the input said `id` and the output schema said
      // `streamId`, and Gemini was sometimes returning empty
      // recommendations on listing queries because the mapping was
      // unclear ("list me Korean dramas" came back with the right
      // ids buried in the message text but `recommendations: []`).
      Map<String, dynamic> compact(Channel ch) => {
            'streamId': ch.streamId,
            'title': ch.name,
            'type': ch.type,
            if (ch.genre != null && ch.genre!.isNotEmpty) 'genre': ch.genre,
            if (ch.year != null && ch.year!.isNotEmpty) 'year': ch.year,
            if (ch.rating != null) 'rating': ch.rating,
          };

      // Dedupe queryMatches against librarySample (and itself by id)
      // so the AI doesn't see the same id twice in different buckets.
      final sampleIds = librarySample.map((c) => c.streamId).toSet();
      final dedupedMatches = <Channel>[];
      final seenMatchIds = <int>{};
      for (final c in queryMatches) {
        if (sampleIds.contains(c.streamId)) continue;
        if (!seenMatchIds.add(c.streamId)) continue;
        dedupedMatches.add(c);
      }

      // recentAdditions is its own labelled pool. Keep it free of ids
      // already shown in the rating sample so the AI doesn't double-
      // count, but it intentionally CAN overlap with queryMatches —
      // the recency label is the signal that matters here.
      final dedupedRecent = recentAdditions
          .where((c) => !sampleIds.contains(c.streamId))
          .toList();

      final contextBlob = <String, dynamic>{
        'recentlyWatched': recentlyWatched.map(compact).toList(),
        'favorites': favorites.map(compact).toList(),
        // recentAdditions: freshest titles by catalogue add-date,
        // newest first. The model is told (system prompt) to pull
        // from here whenever the user asks about new / "yeni" content.
        if (dedupedRecent.isNotEmpty)
          'recentAdditions': dedupedRecent.map(compact).toList(),
        // queryMatches: pre-search results matching the user's latest
        // question. The standard top-rated `library` slice often
        // doesn't contain niche categories (e.g. Korean dramas in a
        // TR-localised catalogue) so the AI used to say "yok" when
        // asked about them. queryMatches surfaces those items.
        if (dedupedMatches.isNotEmpty)
          'queryMatches': dedupedMatches.map(compact).toList(),
        'library': librarySample.map(compact).toList(),
        // categoryOverview: tiny `[{name, type, count}]` list of the
        // top non-hidden categories in the catalogue. Gives the AI
        // a structural view of what exists so it can suggest browsing
        // a category by name when asked about something outside the
        // sample.
        if (categoryOverview.isNotEmpty)
          'categories': categoryOverview,
        // tasteProfile: aggregate weighted view. Lets the AI weigh
        // tie-breakers between equally-good candidates by reading
        // the actual category/actor/director scores instead of
        // re-deriving them from the favourites/history lists every
        // turn. Empty {} on cold-start profiles.
        if (tasteProfile.isNotEmpty) 'tasteProfile': tasteProfile,
        // currentEpisode: spoiler-awareness hint. When present the
        // system prompt switches into "spoiler-safe" mode and the
        // AI must not reveal anything from past this episode.
        if (currentEpisode != null) 'currentEpisode': currentEpisode,
      };

      // Build Gemini chat history. The first user turn carries the
      // context blob inline as JSON; subsequent turns only carry
      // their own text. We could re-send context every turn for
      // robustness, but at conversation-level token budgets, that
      // burns the user's quota for no gain.
      final contents = <Map<String, dynamic>>[];
      for (var i = 0; i < conversation.length; i++) {
        final turn = conversation[i];
        final isFirstUserTurn = i == 0 && turn.fromUser;
        final text = isFirstUserTurn
            ? 'CONTEXT_JSON: ${jsonEncode(contextBlob)}\n\nUSER: ${turn.text}'
            : turn.text;
        contents.add({
          'role': turn.fromUser ? 'user' : 'model',
          'parts': [
            {'text': text},
          ],
        });
      }

      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': _buildTonightSystemPrompt(targetLanguage)},
            ],
          },
          'contents': contents,
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _tonightResponseSchema,
            'temperature': 0.7, // some warmth in phrasing
            // Bumped to 4096 — listing queries with 10+ Korean dramas
            // each carrying a one-sentence reason can easily blow
            // past 2048 tokens, especially in Turkish where token
            // density is lower than English. Truncated JSON would
            // come back unparseable and the user would see "yok"
            // again.
            'maxOutputTokens': 4096,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] recommendForTonight status=${res.statusCode} body=${res.data}');
        return null;
      }

      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      // Same prose-tolerance trick as parseSearchQuery: pull out the
      // outermost JSON object in case Gemini wraps it in prose.
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = text.substring(start, end + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] recommendForTonight JSON decode failed: $e');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;

      return TonightResponse.fromJson(decoded);
    } catch (e) {
      debugPrint('[Gemini] recommendForTonight failed: $e');
      return null;
    }
  }

  // ── Agentic chat (function calling) ──────────────────────────────────────

  /// Tool declarations the agent can call. Read tools return data to
  /// the model; action tools perform side effects via [onToolCall].
  /// `presentRecommendations` is the model's way to deliver the
  /// familiar message + recommendation cards + follow-up chips.
  static const List<Map<String, dynamic>> _agentTools = [
    {
      'functionDeclarations': [
        {
          'name': 'searchLibrary',
          'description':
              'Search the user\'s OWN library semantically. Returns matching '
                  'titles with their streamId/type/genre so you can act on '
                  'them. Use before recommending or playing so you reference '
                  'real ids.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'query': {'type': 'STRING'},
              'type': {
                'type': 'STRING',
                'description': "optional 'movie' or 'series'",
              },
            },
            'required': ['query'],
          },
        },
        {
          'name': 'searchLiveChannels',
          'description':
              'Search LIVE TV channels by name (e.g. "CNN", "beIN Sports", '
                  '"haber"). Returns channels with streamId/type=live so you '
                  'can play one. Use this for live TV, not searchLibrary.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'query': {'type': 'STRING'},
            },
            'required': ['query'],
          },
        },
        {
          'name': 'getLiveNowOnAir',
          'description':
              'What is on LIVE right now: a list of channels with their '
                  'current programme (title + start/stop). Use for "şu an ne '
                  'var" / "canlıda ne oynuyor". Takes no arguments.',
          // No `parameters` — Gemini rejects an empty properties object,
          // which 400s the whole request.
        },
        {
          'name': 'findPrograms',
          'description':
              'Search the EPG for UPCOMING programmes by title (e.g. a match, '
                  'a show). Returns channel + programme title + startEpochMs / '
                  'stopEpochMs. Use the startEpochMs to set a reminder, or '
                  'playContent on the channel if it is already on.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'query': {'type': 'STRING'},
            },
            'required': ['query'],
          },
        },
        {
          'name': 'playContent',
          'description': 'Start playing a title immediately on this device.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'streamId': {'type': 'INTEGER'},
              'type': {'type': 'STRING'},
            },
            'required': ['streamId', 'type'],
          },
        },
        {
          'name': 'openDetail',
          'description': 'Open a title\'s detail page (no playback).',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'streamId': {'type': 'INTEGER'},
              'type': {'type': 'STRING'},
            },
            'required': ['streamId', 'type'],
          },
        },
        {
          'name': 'addFavorite',
          'description': 'Add a title to the user\'s favourites.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'streamId': {'type': 'INTEGER'},
              'type': {'type': 'STRING'},
            },
            'required': ['streamId', 'type'],
          },
        },
        {
          'name': 'removeFavorite',
          'description': 'Remove a title from the user\'s favourites.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'streamId': {'type': 'INTEGER'},
              'type': {'type': 'STRING'},
            },
            'required': ['streamId', 'type'],
          },
        },
        {
          'name': 'switchProfile',
          'description': 'Switch the active viewing profile by name.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'name': {'type': 'STRING'},
            },
            'required': ['name'],
          },
        },
        {
          'name': 'setReminder',
          'description':
              'Set a reminder for a title or a live programme at a given '
                  'time. Provide epochMs (ms since epoch) for when to fire.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'streamId': {'type': 'INTEGER'},
              'type': {'type': 'STRING'},
              'title': {'type': 'STRING'},
              'epochMs': {'type': 'INTEGER'},
            },
            'required': ['title', 'epochMs'],
          },
        },
        {
          'name': 'presentRecommendations',
          'description':
              'Deliver your final answer to the user: a short message, '
                  'optional recommendation cards (streamId + one-line reason), '
                  'and 3-4 follow-up chips. Call this when you are done — it '
                  'ends your turn.',
          'parameters': {
            'type': 'OBJECT',
            'properties': {
              'message': {'type': 'STRING'},
              'recommendations': {
                'type': 'ARRAY',
                'items': {
                  'type': 'OBJECT',
                  'properties': {
                    'streamId': {'type': 'INTEGER'},
                    'reason': {'type': 'STRING'},
                  },
                },
              },
              'followUps': {
                'type': 'ARRAY',
                'items': {'type': 'STRING'},
              },
            },
            'required': ['message'],
          },
        },
      ],
    },
  ];

  /// Run the agent loop. [onToolCall] executes an action tool and
  /// returns a small JSON result the model sees next. The loop ends
  /// when the model calls `presentRecommendations` or replies with
  /// plain text. Returns the resulting [TonightResponse].
  Future<TonightResponse?> runAgent({
    required List<({bool fromUser, String text})> conversation,
    required String contextJson,
    required String targetLanguage,
    required Future<Map<String, dynamic>> Function(
            String name, Map<String, dynamic> args)
        onToolCall,
    int maxRounds = 6,
  }) async {
    if (_apiKey.isEmpty || conversation.isEmpty) return null;
    try {
      final contents = <Map<String, dynamic>>[];
      for (var i = 0; i < conversation.length; i++) {
        final turn = conversation[i];
        final isFirstUser = i == 0 && turn.fromUser;
        contents.add({
          'role': turn.fromUser ? 'user' : 'model',
          'parts': [
            {
              'text': isFirstUser
                  ? 'CONTEXT_JSON: $contextJson\n\nUSER: ${turn.text}'
                  : turn.text
            },
          ],
        });
      }

      for (var round = 0; round < maxRounds; round++) {
        final res = await _dio.post<Map<String, dynamic>>(
          '$_endpoint/$_model:generateContent',
          queryParameters: {'key': _apiKey},
          data: {
            'systemInstruction': {
              'parts': [
                {'text': _buildAgentSystemPrompt(targetLanguage)},
              ],
            },
            'contents': contents,
            'tools': _agentTools,
            'generationConfig': {
              'temperature': 0.6,
              'maxOutputTokens': 2048,
            },
          },
        );
        if (res.statusCode != 200) {
          debugPrint('[Gemini] runAgent status=${res.statusCode} '
              'body=${res.data}');
          return null;
        }
        final body = res.data;
        if (body is! Map<String, dynamic>) return null;
        final candidates = body['candidates'];
        if (candidates is! List || candidates.isEmpty) return null;
        final content = (candidates.first as Map)['content'];
        if (content is! Map) return null;
        final parts = (content['parts'] as List?) ?? const [];

        // Collect any function calls in this turn.
        final calls = <Map<String, dynamic>>[];
        final textBuf = StringBuffer();
        for (final p in parts) {
          if (p is! Map) continue;
          if (p['functionCall'] is Map) {
            calls.add((p['functionCall'] as Map).cast<String, dynamic>());
          } else if (p['text'] is String) {
            textBuf.write(p['text']);
          }
        }

        if (calls.isEmpty) {
          // Plain-text final answer.
          final t = textBuf.toString().trim();
          return TonightResponse(message: t, recommendations: const []);
        }

        // Echo the model's content back, then answer each call.
        contents.add({'role': 'model', 'parts': parts});
        final responseParts = <Map<String, dynamic>>[];
        for (final call in calls) {
          final name = (call['name'] ?? '') as String;
          final args = (call['args'] is Map)
              ? (call['args'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};

          if (name == 'presentRecommendations') {
            // Terminal: build the final response from the model's args.
            return TonightResponse.fromJson(args);
          }

          Map<String, dynamic> result;
          try {
            result = await onToolCall(name, args);
          } catch (e) {
            result = {'error': e.toString()};
          }
          responseParts.add({
            'functionResponse': {'name': name, 'response': result},
          });
        }
        contents.add({'role': 'function', 'parts': responseParts});
      }
      // Ran out of rounds without a terminal call.
      return const TonightResponse(message: '', recommendations: []);
    } catch (e) {
      debugPrint('[Gemini] runAgent failed: $e');
      return null;
    }
  }

  String _buildAgentSystemPrompt(String lang) => '''
${_buildTonightSystemPrompt(lang)}

── AGENT MODE ──
You also have TOOLS and can take actions on the user's behalf:
  * searchLibrary(query, type?) — search their OWN movie/series library;
    call this to ground yourself in real streamIds before
    recommending/acting. (Movies & series only.)
  * searchLiveChannels(query) — find LIVE TV channels by name.
  * getLiveNowOnAir() — what's airing live right now.
  * findPrograms(query) — search the EPG for upcoming programmes
    (matches, shows); returns startEpochMs you can pass to setReminder.
  * playContent(streamId, type) — start playback now.
  * openDetail(streamId, type) — open a title's page.
  * addFavorite / removeFavorite(streamId, type).
  * switchProfile(name).
  * setReminder(title, epochMs, streamId?, type?) — epochMs is the
    absolute fire time in milliseconds since the Unix epoch.
  * presentRecommendations(message, recommendations[], followUps[]) —
    your FINAL answer with cards + chips. Call it when done.

Rules:
  * When the user asks to DO something ("aç", "oynat", "favorilere
    ekle", "hatırlat", "profili değiştir"), call the matching action
    tool — don't just describe it.
  * Prefer searchLibrary to find the right streamId instead of
    guessing one.
  * To answer a recommendation/listing/discussion question, finish by
    calling presentRecommendations (put cards in recommendations[] and
    chips in followUps[]). For a pure action ("şunu aç"), you may end
    with a short presentRecommendations message confirming what you did.
  * Always respond in $lang.
''';

  /// Four "fix this plot" use-cases the detail page wires to small
  /// inline links underneath the synopsis text. Each maps to a
  /// different system prompt — the user-visible action stays the
  /// same shape ("ask Gemini → swap the text"), only the framing
  /// differs.
  ///
  /// Returns the AI-produced plot text, or `null` on any failure.
  /// Caller falls back to keeping the original.
  ///
  /// All metadata fields are optional but cumulative — pass as
  /// many as the catalog has. The model gets a stronger signal to
  /// work with, especially for `fillIn` / `detailedInfo` where it
  /// has to synthesise from this metadata when it doesn't
  /// recognise the title.
  Future<String?> enrichPlot({
    required String title,
    String? year,
    String? genre,
    String? director,
    String? cast,
    double? rating,
    String? originalPlot,
    required PlotEnrichMode mode,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty) return null;

    final systemPrompt = switch (mode) {
      PlotEnrichMode.translate => '''
You translate movie/series plot summaries into the user's language
($targetLanguage). Keep the same level of detail. Reply with the
translation only — no preamble, no quotes, no "Here is the
translation:" framing. Output plain text.
''',
      PlotEnrichMode.summarize => '''
You write spoiler-free summaries of movie/series plots in the user's
language ($targetLanguage). Reduce to 2–3 sentences that establish
the premise and tone without revealing twists, endings, or
mid-story turns. Reply with the summary only — plain text, no
markdown headings, no preamble.
''',
      PlotEnrichMode.fillIn => '''
The user is viewing a title whose plot field is empty or missing.
Reply in the user's language ($targetLanguage), 2-3 sentence plot
description, plain text, no preamble, no disclaimers.

If you have specific knowledge of the title, use it. If not, fall
back to the metadata you were given (title, year, genre, director,
cast) and synthesise an informative one-paragraph blurb from that —
title parsing alone often signals the premise ("Phantom Lawyer"
+ drama genre + 2026 → a drama about a lawyer with some
supernatural element). Never reply with "UNKNOWN" or refuse to
answer — produce something useful from whatever signal is present.
''',
      PlotEnrichMode.detailedInfo => '''
The user wants comprehensive information about this title, in
their language ($targetLanguage). The plot field they currently
see is unreliable (often machine-translated, truncated, or in
the wrong language) — write a richer description from your
general knowledge instead.

Cover these in 4–6 short paragraphs, separated by blank lines:
  1. Premise — what's the setup, who's the protagonist
  2. Tone & style — pace, atmosphere, signature elements
  3. Themes — what the story is really *about*
  4. Why it stands out — what's notable (awards, director,
     cultural impact, unique angle)
  5. Recommended viewer — who'll enjoy this most

Spoiler-free. No reveals, no ending hints, no twists. Plain text
with paragraph breaks. No markdown headings, no preamble.

When you don't recognise the specific title, DO NOT reply with
"UNKNOWN" or refuse. Instead synthesise the most informative
write-up you can from the metadata supplied (title, year, genre,
director, cast). Use the genre to set tone, the title to infer
premise, the director and cast to flag style — even a sparse
write-up is more useful to the viewer than no write-up. If you
need to express low confidence, do it inline with phrasing like
"görünüşe göre" / "muhtemelen" — never with a bare refusal.
''',
    };

    // Build the metadata header — same for all modes, gives the
    // model maximal signal to work with. detailedInfo and fillIn
    // *especially* benefit from director/cast because they have
    // to synthesise without the original plot text.
    final metaLines = <String>[
      'Title: $title${year != null && year.isNotEmpty ? " ($year)" : ""}',
      if (genre != null && genre.isNotEmpty) 'Genre: $genre',
      if (director != null && director.isNotEmpty) 'Director: $director',
      if (cast != null && cast.isNotEmpty) 'Cast: $cast',
      if (rating != null) 'Rating: ${rating.toStringAsFixed(1)}/10',
    ];

    final userTurn = switch (mode) {
      PlotEnrichMode.translate ||
      PlotEnrichMode.summarize =>
        '${metaLines.join("\n")}\n\nPlot:\n${originalPlot ?? ""}',
      PlotEnrichMode.fillIn ||
      PlotEnrichMode.detailedInfo =>
        // Send the existing plot too, even if it's poor — gives
        // the model another hook (sometimes the metadata is wrong
        // or in another language but the plot has the real
        // premise).
        originalPlot != null && originalPlot.trim().isNotEmpty
            ? '${metaLines.join("\n")}\n\nExisting (possibly poor) plot text:\n$originalPlot'
            : metaLines.join("\n"),
    };

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'temperature': mode == PlotEnrichMode.translate ? 0.2 : 0.5,
            // detailedInfo writes 4–6 short paragraphs. Token budget
            // history:
            //   *  900 → first try, Turkish kept getting clipped
            //      mid-word for any prose-heavy answer.
            //   * 1800 → still clipped — Turkish output averages
            //      ~2 tokens per syllable with Gemini's BPE, much
            //      heavier than English.
            //   * 4096 → comfortable headroom; the model still
            //      stops at "natural" lengths for shorter titles
            //      and only stretches when the content warrants
            //      it. Well under the 8192 per-response cap.
            //
            // Other modes (translate/summarize/fillIn) stay at 500
            // because they're explicitly short-form and a runaway
            // response is more annoying than a truncated one.
            'maxOutputTokens':
                mode == PlotEnrichMode.detailedInfo ? 4096 : 500,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] enrichPlot status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString().trim();
      if (text == null || text.isEmpty) return null;
      // Legacy compatibility — earlier prompt versions instructed
      // the model to reply with "UNKNOWN" for unrecognised titles.
      // We now ask the model to synthesise from metadata instead,
      // but a stale cache or older prompt run can still emit the
      // sentinel; treat it as a soft failure and let the caller
      // keep the original plot.
      if (text.toUpperCase() == 'UNKNOWN') return null;
      return text;
    } catch (e) {
      debugPrint('[Gemini] enrichPlot failed: $e');
      return null;
    }
  }

  /// Spoiler-free recap of a series, scoped to "what happened up to
  /// the episode the user is about to play".
  ///
  /// Drives the small "Şimdiye kadar olanı hatırlat" link that
  /// appears next to the Continue Watching button on series detail
  /// pages. The user has typically been away from a series for
  /// days/weeks and needs the broad strokes back before resuming —
  /// without us blowing the next episode's twists.
  ///
  /// `nextEpisodeLabel` is the season/episode tag attached to the
  /// upcoming play (e.g. `"S1E10"`). The system prompt tells Gemini
  /// to recap *up to but not including* that episode, so a user
  /// resuming at S1E10 gets S1E1–S1E9 caught up.
  ///
  /// Returns the recap text, or `null` if Gemini can't confidently
  /// summarise (UNKNOWN sentinel) or the call fails for any reason.
  Future<String?> recapSeriesUpTo({
    required String title,
    String? year,
    String? genre,
    String? plot,
    required String nextEpisodeLabel,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || title.isEmpty) return null;

    final systemPrompt = '''
You write spoiler-free recaps of TV series for viewers who are about
to resume after a break. Output language: $targetLanguage.

The user is about to watch the episode labeled $nextEpisodeLabel.
Recap events that happened in earlier episodes only — strictly
*before* $nextEpisodeLabel. Never mention anything that happens at
or after that episode. Do not name the upcoming episode.

Cover:
  • Where the story started (premise)
  • The main characters and their arcs so far
  • Where the story stands right before $nextEpisodeLabel

Keep it to 3–5 short paragraphs separated by blank lines. Plain
text. No markdown headings, no preamble, no "Here's the recap:"
framing.

If you genuinely don't recognise the series or can't confidently
recap it without inventing details, reply with the single word
"UNKNOWN" (uppercase, no punctuation) — caller drops the result.
''';

    final userTurn = StringBuffer()
      ..writeln('Series: $title${year != null && year.isNotEmpty ? " ($year)" : ""}');
    if (genre != null && genre.isNotEmpty) {
      userTurn.writeln('Genre: $genre');
    }
    if (plot != null && plot.trim().isNotEmpty) {
      userTurn
        ..writeln()
        ..writeln('Synopsis on file (may be incomplete):')
        ..writeln(plot);
    }

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn.toString()},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.5,
            'maxOutputTokens': 900,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] recapSeriesUpTo status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString().trim();
      if (text == null || text.isEmpty) return null;
      if (text.toUpperCase() == 'UNKNOWN') return null;
      return text;
    } catch (e) {
      debugPrint('[Gemini] recapSeriesUpTo failed: $e');
      return null;
    }
  }

  /// Curated "similar content" picks, grouped by axis.
  ///
  /// Replaces the token-overlap scoring in the detail screens when
  /// the user has an AI key configured. Gemini receives the full
  /// metadata of the title the user is looking at *plus* a sample
  /// of their library and (optionally) their favourites for
  /// personalisation, and returns 2-4 axis-grouped buckets:
  ///
  ///   • "Aynı yönetmenden" / "From the same director"
  ///   • "Aynı oyuncularla" / "With the same cast"
  ///   • "Benzer atmosfer ve tempo" / "Similar tone & pacing"
  ///   • "Aynı dönem ve coğrafya" / "Same era & origin"
  ///
  /// …with 2-4 items per bucket, each carrying a one-sentence
  /// justification specific to that axis. Axis labels are in the
  /// user's language so the UI doesn't need to translate them.
  ///
  /// Returns `null` on failure; caller falls back to the existing
  /// scoring algorithm in that case so the detail page never ends
  /// up with an empty "Benzer içerikler" rail.
  Future<List<SimilarGroup>?> findSimilarContent({
    required String currentTitle,
    required String currentType,
    String? currentYear,
    String? currentGenre,
    String? currentPlot,
    String? currentDirector,
    String? currentCast,
    required List<Map<String, dynamic>> librarySample,
    List<Map<String, dynamic>> favorites = const [],
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || librarySample.isEmpty) return null;

    final currentBlob = <String, dynamic>{
      'title': currentTitle,
      'type': currentType,
      if (currentYear != null && currentYear.isNotEmpty) 'year': currentYear,
      if (currentGenre != null && currentGenre.isNotEmpty)
        'genre': currentGenre,
      if (currentDirector != null && currentDirector.isNotEmpty)
        'director': currentDirector,
      if (currentCast != null && currentCast.isNotEmpty) 'cast': currentCast,
      if (currentPlot != null && currentPlot.isNotEmpty) 'plot': currentPlot,
    };

    final systemPrompt = '''
You are a film and TV recommendation specialist with deep knowledge
of casts, directors, themes, and cinematic style. You speak the
user's language ($targetLanguage) fluently.

The user is looking at one specific title (CURRENT_ITEM JSON in the
first user turn) and you have a sample of their library
(LIBRARY_SAMPLE). Pick 6-12 items total from LIBRARY_SAMPLE that the
user would enjoy, **grouped by axis**. You may also use FAVORITES
as a hint about their taste.

Acceptable axes (use exact wording you choose, in $targetLanguage):
  • Same director — when LIBRARY has another work by the current
    item's director or a director with very similar sensibility.
  • Same lead actor(s) — when one or more cast members from the
    current item appear in LIBRARY items.
  • Similar tone & pacing — atmospheric / mood-based matches that
    cross genre lines.
  • Same era & origin — country + decade clusters (e.g. "Korean
    crime drama, 2020+").
  • Same theme — thematic matches (e.g. "Father-son drama",
    "Heist comedies").

Rules:
  1. Use **only** streamIds that appear in LIBRARY_SAMPLE. Never
     invent ids.
  2. 2-4 groups. Each group must have 2-4 items.
  3. Each item's `reason` must be **specific to this axis** —
     "shares director Hong Sung-chang" not just "similar genre".
  4. `reason` and `axisLabel` / `axisSubtitle` MUST be in
     $targetLanguage. Plain text, one sentence each, no markdown.
  5. Don't list the current item itself.
  6. If LIBRARY_SAMPLE has nothing genuinely similar, return an
     empty groups array — better to show nothing than reach.

Return strict JSON matching the response schema.
''';

    final userTurn = 'CURRENT_ITEM: ${jsonEncode(currentBlob)}\n'
        'LIBRARY_SAMPLE: ${jsonEncode(librarySample)}\n'
        '${favorites.isNotEmpty ? "FAVORITES: ${jsonEncode(favorites)}\n" : ""}';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _similarResponseSchema,
            'temperature': 0.6,
            'maxOutputTokens': 2048,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] findSimilarContent status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      // Same prose-tolerance trick as other methods.
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = text.substring(start, end + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] findSimilarContent JSON decode failed: $e');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;

      final rawGroups = decoded['groups'];
      if (rawGroups is! List) return null;
      final groups = <SimilarGroup>[];
      for (final g in rawGroups) {
        if (g is Map<String, dynamic>) {
          final group = SimilarGroup.fromJson(g);
          if (group != null && !group.isEmpty) {
            groups.add(group);
          }
        }
      }
      return groups;
    } catch (e) {
      debugPrint('[Gemini] findSimilarContent failed: $e');
      return null;
    }
  }

  static const Map<String, dynamic> _similarResponseSchema = {
    'type': 'OBJECT',
    'properties': {
      'groups': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'axisLabel': {'type': 'STRING'},
            'axisSubtitle': {'type': 'STRING', 'nullable': true},
            'items': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'streamId': {'type': 'INTEGER'},
                  'reason': {'type': 'STRING'},
                },
                'required': ['streamId', 'reason'],
              },
            },
          },
          'required': ['axisLabel', 'items'],
        },
      },
    },
    'required': ['groups'],
  };

  /// Library-aware semantic search.
  ///
  /// The other "search" method on this service ([parseSearchQuery])
  /// only extracts structured filters from the user's wording —
  /// the actual matching is still keyword LIKE in the repository.
  /// That works for categorical queries (genre, year, cast name)
  /// but falls apart on conceptual / thematic queries where the
  /// catalog's `plot` field doesn't carry the obvious vocabulary
  /// (an apocalyptic film whose plot says "in a world without
  /// fuel…").
  ///
  /// This method takes the user's query *plus a sample of the
  /// library* and lets Gemini do the matching directly, leaning on
  /// its general knowledge of titles. It returns the
  /// stream-ids of items that fit the query (only ids that actually
  /// appear in the supplied sample — no hallucinations) along with
  /// a short user-language reason per pick.
  ///
  /// Returns `null` on any failure; caller falls back to the
  /// keyword path. Empty list = AI consulted but found nothing.
  Future<List<({int streamId, String reason})>?> curateLibraryByQuery({
    required String query,
    required List<Map<String, dynamic>> librarySample,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || query.trim().isEmpty || librarySample.isEmpty) {
      return null;
    }

    final systemPrompt = '''
You are a film and TV curator with deep knowledge of titles across
languages and decades. The user types a query (any language, often
Turkish) describing what they want to watch.

LIBRARY_SAMPLE is a candidate pool drawn from the user's library
(plain keyword hits + genre-filter matches + a wide top-rated
cross-section). It may carry up to ~800 items in a single
pipe-separated rows wrapper (the first row is the column header,
each subsequent row is one library item). Parse the rows yourself
— `id|title|type|year|genre|director|cast|rating`. Items may
include false positives that look like matches by name alone —
your job is to **filter and rank using actual knowledge of each
title**.

Your output is the top 12–25 items, ranked by genuine fit, with a
one-sentence justification each.

USE REAL KNOWLEDGE, NOT KEYWORD HEURISTICS:
  - "Korku Seansı" → actually horror, include.
  - "Korkusuz" (Jet Li, 2006) → action drama, NOT horror — exclude
    for query "korku" even though the name contains the keyword.
  - "Korkunç Bir Film" / "Scary Movie" → horror-comedy parody, can
    be included for "korku" but flag the parody angle in the reason.
  - "Hereditary", "The Conjuring", "It Chapter Two" → core horror,
    include even if the title doesn't contain the query word.

For thematic queries ("dünyanın sonu konulu", "seri katil",
"yapay zeka"), reach across the whole sample using your knowledge
of each title's actual premise — title text doesn't have to
contain the theme word.

Rules:
  1. Use only streamIds that appear in LIBRARY_SAMPLE. Never
     invent ids.
  2. 12–25 picks ideally, ordered best-first. Quality over
     quantity — empty list is fine when nothing really fits.
  3. DROP candidates that only superficially match by name.
  4. `reason` is one short sentence in $targetLanguage with
     concrete facts (director, cast, premise, era, vibe). Generic
     "bu bir korku filmi" is useless — say "James Wan'in Conjuring
     evrenine ait, paranormal aktivite teması" instead.
  5. If the query refers to a specific title, treat exact / fuzzy
     name matches as obvious top picks (with a brief identifying
     reason).

Return strict JSON: {"picks":[{"streamId":<int>,"reason":<string>},…]}.
''';

    final userTurn =
        'QUERY: $query\n\nLIBRARY_SAMPLE: ${jsonEncode(librarySample)}';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _curateResponseSchema,
            'temperature': 0.3,
            'maxOutputTokens': 2048,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] curateLibraryByQuery status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = text.substring(start, end + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] curateLibraryByQuery JSON decode failed: $e');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;

      final raw = decoded['picks'];
      if (raw is! List) return null;
      final picks = <({int streamId, String reason})>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        final reason = item['reason']?.toString().trim() ?? '';
        if (sid != null && sid > 0 && reason.isNotEmpty) {
          picks.add((streamId: sid, reason: reason));
        }
      }
      return picks;
    } catch (e) {
      debugPrint('[Gemini] curateLibraryByQuery failed: $e');
      return null;
    }
  }

  static const Map<String, dynamic> _curateResponseSchema = {
    'type': 'OBJECT',
    'properties': {
      'picks': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'streamId': {'type': 'INTEGER'},
            'reason': {'type': 'STRING'},
          },
          'required': ['streamId', 'reason'],
        },
      },
    },
    'required': ['picks'],
  };

  /// Dashboard "Sana Özel" personalised recommendations.
  ///
  /// Different from `recommendForTonight` (interactive chat) — this
  /// is the passive daily-refresh rail. Gemini receives the user's
  /// recent watch history + favourites + a library cross-section
  /// and picks ~12–15 items that fit the user's taste profile, in
  /// ranked order with concrete reasons.
  ///
  /// Returns `null` on failure; caller hides the rail entirely so
  /// the dashboard never shows broken AI surfaces.
  Future<List<({int streamId, String reason})>?> recommendForYou({
    required List<Map<String, dynamic>> recentlyWatched,
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> librarySample,
    required String targetLanguage,
    int varietySeed = 0,
    List<Map<String, dynamic>> moreLikeAnchors = const [],
    List<Map<String, dynamic>> avoidTitles = const [],
    Map<String, dynamic> tasteProfile = const {},
  }) async {
    if (_apiKey.isEmpty || librarySample.isEmpty) return null;

    final systemPrompt = '''
You curate a personalised "For You" rail on the dashboard of an
IPTV / streaming app. The user comes back to this rail every time
they open the app, so the picks should feel intentional — never
generic "popular movies", always grounded in this user's taste.

Inputs (in the first user turn, JSON):
  * FAVORITES — items the user explicitly saved. STRONGEST taste
    signal.
  * RECENTLY_WATCHED — what they've been viewing in the last days.
    Strong but noisier than favourites.
  * MORE_LIKE_THESE (optional) — titles the user explicitly flagged
    via the ⋯ menu as "I want more of this". Treat at favourite
    weight or higher when they appear.
  * AVOID_THESE (optional) — titles the user explicitly disliked
    via the ⋯ menu. Do NOT recommend them. More importantly,
    DIVERGE from them on tone / genre / director — these are
    counter-signals, not just blacklist entries.
  * LIBRARY — a cross-section of the catalogue, pipe-separated rows
    with header `id|title|type|year|genre|director|cast|rating`.

Your job: pick 12–15 items from LIBRARY that match this user's
taste, with explicit weight on FAVORITES > RECENTLY_WATCHED. Mix:
  * Direct echoes — same director / cast / category / sub-genre
    as their favourites or recent watches.
  * Tasteful jumps — items that fit the *vibe* of what they love
    but explore a related corner they haven't tried yet.

Rules:
  1. Only return streamIds present in LIBRARY.
  2. 12–15 picks, ordered by personal fit (best first).
  3. `reason` is ONE short sentence in $targetLanguage, with
     concrete facts that name the signal you used: same director
     ("Aynı yönetmenden — X"), same lead actor ("Y'nin başka bir
     filmi"), same category ("KOMEDi & ROMANTiK favorilerine
     benziyor"), parallel vibe ("Phantom Lawyer'a benzer kara
     mizah"). Generic "you might like this" is useless.
  4. Skip items already in RECENTLY_WATCHED or FAVORITES.
  5. When a favourite and a recently-watched item disagree on
     genre, lean toward the favourite — saving beats sampling.
  6. Spread across types where it makes sense (movie + series).
  7. If FAVORITES + RECENTLY_WATCHED are both empty, fall back
     to highest-rated LIBRARY items + variety across categories.

Return strict JSON: {"picks":[{"streamId":<int>,"reason":<str>},…]}.
''';

    // When the user explicitly hits the refresh button on the rail
    // the provider bumps varietySeed. Folding it into the user turn
    // nudges Gemini's sampler into a different region of the
    // candidate space so the rail visibly changes rather than
    // returning the same picks the user just saw.
    final varietyHint = varietySeed > 0
        ? '\nVARIETY_SEED: $varietySeed — the user just asked for a '
            'fresh pick, so prefer different items from your previous '
            'response, explore adjacent genres/eras, and reshuffle the '
            'order.'
        : '';

    // Explicit feedback signals — when the user has used the ⋯
    // menu on rec cards to flag items as "more like this" or "don't
    // suggest". We hand both to the model as named lists so it can
    // boost similar items and avoid known-bad picks.
    final moreLikeHint = moreLikeAnchors.isEmpty
        ? ''
        : '\nMORE_LIKE_THESE: ${jsonEncode(moreLikeAnchors)} — '
            'strong positive anchors, treat closer in weight to '
            'FAVORITES than to RECENTLY_WATCHED.';
    final avoidHint = avoidTitles.isEmpty
        ? ''
        : '\nAVOID_THESE: ${jsonEncode(avoidTitles)} — the user '
            'explicitly disliked these titles. Do NOT recommend them, '
            'and prefer picks that DIVERGE from them on genre, tone, '
            'or director rather than echo them.';

    // TasteProfile aggregate — pre-computed per-category, per-actor,
    // per-director affinity scores. Lets the AI rank candidates
    // against weighted preferences instead of re-deriving "this
    // user likes drama" from raw history every call.
    final profileHint = tasteProfile.isEmpty
        ? ''
        : '\nTASTE_PROFILE: ${jsonEncode(tasteProfile)} — '
            'aggregate weighted view of the user\'s preferences. '
            'Higher scores = stronger affinity. Use this as the '
            'TIE-BREAKER between equally-good library candidates. '
            'If isColdStart=true, lean on critical acclaim rather '
            'than these scores.';

    final userTurn = 'RECENTLY_WATCHED: ${jsonEncode(recentlyWatched)}\n'
        'FAVORITES: ${jsonEncode(favorites)}\n'
        'LIBRARY: ${jsonEncode(librarySample)}$profileHint$moreLikeHint$avoidHint$varietyHint';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _curateResponseSchema,
            // Bump warmth on explicit refresh so the sampler explores
            // further from its previous best response.
            'temperature': varietySeed > 0 ? 0.95 : 0.6,
            'maxOutputTokens': 2048,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] recommendForYou status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      final startIdx = text.indexOf('{');
      final endIdx = text.lastIndexOf('}');
      if (startIdx < 0 || endIdx <= startIdx) return null;
      final jsonStr = text.substring(startIdx, endIdx + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] recommendForYou JSON decode failed: $e');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;

      final raw = decoded['picks'];
      if (raw is! List) return null;
      final picks = <({int streamId, String reason})>[];
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        final reason = item['reason']?.toString().trim() ?? '';
        if (sid != null && sid > 0 && reason.isNotEmpty) {
          picks.add((streamId: sid, reason: reason));
        }
      }
      return picks;
    } catch (e) {
      debugPrint('[Gemini] recommendForYou failed: $e');
      return null;
    }
  }

  /// Weekly digest — picks 3-5 newly-added items the AI thinks
  /// match the user's taste, plus a one-sentence headline ("Bu hafta
  /// için 4 yeni keşif").
  ///
  /// Distinguishes itself from [recommendForYou] by being explicitly
  /// scoped to fresh-this-week content. The dashboard banner only
  /// surfaces when there's enough new content AND the AI can find
  /// at least one match. Otherwise we hide rather than show a stale
  /// "this week" widget.
  Future<({String headline, List<({int streamId, String reason})> picks})?>
      weeklyDigest({
    required List<Map<String, dynamic>> recentAdditions,
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> recentlyWatched,
    required String targetLanguage,
    Map<String, dynamic> tasteProfile = const {},
  }) async {
    if (_apiKey.isEmpty || recentAdditions.isEmpty) return null;

    final systemPrompt = '''
You write a one-line weekly digest headline for an IPTV / streaming
app, then pick 3-5 items from RECENT_ADDITIONS that match the
user's taste.

Inputs (first user turn, JSON):
  * RECENT_ADDITIONS — items added to the library in the last 7
    days, pipe-separated rows
    `id|title|type|year|genre|director|cast|rating`.
  * FAVORITES + RECENTLY_WATCHED — taste signals.

Rules:
  1. `headline` is ONE short sentence in $targetLanguage that
     summarises why these picks are worth the user's attention.
     Example: "Sevdiğin kara mizah dizilerinin yeni kuzenleri bu
     hafta kütüphanene düştü." NOT "Here are some new shows".
  2. `picks` is 3-5 streamIds from RECENT_ADDITIONS only — never
     fall back to older items. Quality over quantity.
  3. Each `reason` is ONE short $targetLanguage sentence tying
     the pick to a concrete signal — director / cast / genre /
     vibe overlap with the user's history. "Yeni eklendi" alone
     is NOT a reason.
  4. If RECENT_ADDITIONS is small or doesn't fit the user's
     taste at all, return at minimum 1 pick rather than nothing.

Return strict JSON:
  {"headline":<str>,"picks":[{"streamId":<int>,"reason":<str>},…]}.
''';

    final profileHint = tasteProfile.isEmpty
        ? ''
        : '\nTASTE_PROFILE: ${jsonEncode(tasteProfile)} — '
            'aggregate weighted view of the user\'s preferences. '
            'Use as tie-breaker when ranking new additions. '
            'If isColdStart=true, lean on critical acclaim instead.';

    final userTurn = 'RECENT_ADDITIONS: ${jsonEncode(recentAdditions)}\n'
        'FAVORITES: ${jsonEncode(favorites)}\n'
        'RECENTLY_WATCHED: ${jsonEncode(recentlyWatched)}$profileHint';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': {
              'type': 'object',
              'properties': {
                'headline': {'type': 'string'},
                'picks': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'streamId': {'type': 'integer'},
                      'reason': {'type': 'string'},
                    },
                    'required': ['streamId', 'reason'],
                  },
                },
              },
              'required': ['headline', 'picks'],
            },
            'temperature': 0.6,
            'maxOutputTokens': 1024,
          },
        },
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
      final headline = parsed['headline']?.toString().trim() ?? '';
      final rawPicks = parsed['picks'];
      if (headline.isEmpty || rawPicks is! List) return null;
      final picks = <({int streamId, String reason})>[];
      for (final item in rawPicks) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        final reason = item['reason']?.toString().trim() ?? '';
        if (sid != null && sid > 0 && reason.isNotEmpty) {
          picks.add((streamId: sid, reason: reason));
        }
      }
      if (picks.isEmpty) return null;
      return (headline: headline, picks: picks);
    } catch (e) {
      debugPrint('[Gemini] weeklyDigest failed: $e');
      return null;
    }
  }

  /// One-paragraph career summary for an actor / director, plus a
  /// few iconic roles they're known for. Used by the cast deep-dive
  /// sheet on detail pages — tap a name, get a short brief that
  /// gives context without leaving the app.
  ///
  /// Hands back null on failure so the sheet can collapse the
  /// AI panel and just show the library matches below.
  Future<String?> actorCareerSummary({
    required String name,
    String? appearsInTitle, // current movie/series for grounding
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || name.trim().isEmpty) return null;

    final systemPrompt = '''
You write short career summaries for actors and filmmakers in a
streaming-app modal. Output is ONE compact paragraph in
$targetLanguage, 2-4 sentences max.

Cover, in order:
  1. Who they are — country, era, primary medium.
  2. What they're best known for — 2-3 most iconic roles or films.
  3. A characterising note — recurring genre, working partners,
     awards if landmark (Oscar/Cannes/Palme/etc).

Style rules:
  * No "${"Name"} is a ${"nationality"} actor born in…" boilerplate
    — start with the most interesting fact.
  * Plain prose, no bullet points, no list.
  * Don't invent. If you don't know the person confidently,
    return the empty string.
  * Don't reference the streaming app or any UI.
''';

    final ctxLine = appearsInTitle != null && appearsInTitle.isNotEmpty
        ? '\nCURRENT_TITLE: ${jsonEncode(appearsInTitle)} '
            '(the user is viewing this — you may mention it but '
            'don\'t pad with it).'
        : '';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': 'NAME: ${jsonEncode(name)}$ctxLine'},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 512,
          },
        },
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (e) {
      debugPrint('[Gemini] actorCareerSummary failed: $e');
      return null;
    }
  }

  /// As the user types in the search box, generate 3-5 short
  /// refinement suggestions that disambiguate / narrow the partial
  /// query. Tapping one fills the search field, kicking off the
  /// normal search pipeline.
  ///
  /// Example: user types "uzay" → ["Uzay temalı bilim kurgu",
  /// "Uzay belgeselleri", "Uzay aile filmleri", "Yalnız uzayda
  /// hayatta kalma"]. The chips give the user an instant menu of
  /// directions without having to think of the phrasing.
  ///
  /// Returns null on failure; caller hides the chip row so the
  /// search screen falls back to its pre-AI behaviour.
  Future<List<String>?> suggestSearchRefinements({
    required String partialQuery,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || partialQuery.trim().length < 2) return null;

    final systemPrompt = '''
You are the auto-suggest brain for a streaming app's search box.
The user is mid-typing. Generate 3-5 short refinement suggestions
that branch off their partial query into specific, browseable
directions.

Rules:
  1. Each suggestion is a SHORT noun-phrase in $targetLanguage,
     under 6 words. Not a full sentence.
  2. Cover DIFFERENT directions — don't give 4 variations of the
     same idea. Mix genre, theme, era, format.
  3. Stay grounded — the user typed something concrete; expand
     it, don't invent. "uzay" → space sci-fi, space docs, etc.
     NOT "horror films" (too far).
  4. Skip the trivial echo. "uzay" → DON'T suggest "uzay" alone.
  5. Localised: if the input language differs from
     $targetLanguage, translate the suggestions to
     $targetLanguage.

Return strict JSON: {"suggestions":["<str>","<str>",…]}.
''';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': 'PARTIAL_QUERY: ${jsonEncode(partialQuery)}'},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': {
              'type': 'object',
              'properties': {
                'suggestions': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
              'required': ['suggestions'],
            },
            'temperature': 0.7,
            'maxOutputTokens': 256,
          },
        },
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
      final raw = parsed['suggestions'];
      if (raw is! List) return null;
      final out = <String>[];
      for (final s in raw) {
        final str = s?.toString().trim();
        if (str == null || str.isEmpty) continue;
        if (str.toLowerCase() == partialQuery.trim().toLowerCase()) {
          continue; // skip trivial echo
        }
        out.add(str);
        if (out.length >= 5) break;
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('[Gemini] suggestSearchRefinements failed: $e');
      return null;
    }
  }

  /// Pick 3-5 items the AI thinks deserve front-page billboard
  /// treatment, each paired with a short hook tagline.
  ///
  /// Re-rank the user's Continue Watching rail by current context
  /// (time of day) and their aggregate taste profile, rather than
  /// just last-watched-first.
  ///
  /// Why this matters: the raw history list always surfaces the
  /// most recent thing the user touched, even if that's a horror
  /// they started at 2am and forgot about. At 8 pm with the family
  /// in the living room, the actual answer is a different
  /// half-watched item further down the list. This rerank passes
  /// the whole continue-watching set + the user's
  /// [tasteProfile.toPromptJson] + the current [timeOfDay] bucket
  /// to Gemini and asks for an ordering that fits the moment.
  ///
  /// The AI returns only stream IDs — no new picks, no removals.
  /// We resolve back to the original [Channel] rows on the client
  /// so the user never sees an item that isn't actually in their
  /// history (no hallucination risk).
  ///
  /// Returns null on failure / empty / cold profile — caller
  /// surfaces the raw history list unchanged.
  Future<List<int>?> rerankContinueWatching({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> tasteProfile,
    required String timeOfDay,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || items.length < 3) return null;

    final systemPrompt = '''
You re-rank a user's "Continue Watching" rail. Inputs are JSON:
  * ITEMS — partially-watched items as
    `{"streamId":<int>,"title":<str>,"type":<"movie"|"series">,
       "genre":<str?>,"progressRatio":<0..1>,"daysSinceLastWatch":<int>}`.
  * TASTE_PROFILE — aggregate weighted view of the user's
    preferences (top categories / actors / directors with numeric
    scores).
  * TIME_OF_DAY — current bucket (`sabah` / `öğle` / `akşam` /
    `gece`).

Rules:
  1. Reorder ONLY by streamId. Do NOT add new items, do NOT drop
     items — every input id must appear exactly once in the output.
  2. Pick the order that best fits THIS moment. Examples of how to
     weigh:
       * Evening + a half-watched comedy & a half-watched horror →
         comedy first if the profile leans light, horror first if
         the profile leans dark.
       * High `progressRatio` (>0.6) items that match the current
         mood should be promoted — they're 30 min from feeling
         finished.
       * `daysSinceLastWatch >= 7` items drop because the user
         likely doesn't remember where they were.
       * Items in `avoidedCategories` from TASTE_PROFILE go to the
         bottom regardless of how recently they were touched.
  3. If TASTE_PROFILE.isColdStart=true OR you can't find a clear
     ordering signal, return the items in the same order they
     came in — you're being asked to *improve*, not to invent
     reasoning from nothing.

Output strict JSON:
  {"order":[<int>,<int>,...]}.
''';

    final userTurn = 'ITEMS: ${jsonEncode(items)}\n'
        'TASTE_PROFILE: ${jsonEncode(tasteProfile)}\n'
        'TIME_OF_DAY: $timeOfDay';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': {
              'type': 'OBJECT',
              'properties': {
                'order': {
                  'type': 'ARRAY',
                  'items': {'type': 'INTEGER'},
                },
              },
              'required': ['order'],
            },
            'temperature': 0.3, // deterministic-ish — this is a sort
            'maxOutputTokens': 512,
          },
        },
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[Gemini] rerankContinueWatching JSON decode failed: $e');
        return null;
      }
      final raw = parsed['order'];
      if (raw is! List) return null;
      final order = <int>[];
      for (final v in raw) {
        if (v is int) {
          order.add(v);
        } else if (v is num) {
          order.add(v.toInt());
        }
      }
      // Sanity: AI must have returned exactly the same id set.
      // If not, fall back to the original order — better safe than
      // surfacing a partial / weird rail.
      final inputIds =
          items.map((m) => m['streamId'] as int).toSet();
      if (order.toSet().difference(inputIds).isNotEmpty ||
          inputIds.difference(order.toSet()).isNotEmpty) {
        debugPrint(
            '[Gemini] rerankContinueWatching: id set mismatch, ignoring');
        return null;
      }
      return order;
    } catch (e) {
      debugPrint('[Gemini] rerankContinueWatching failed: $e');
      return null;
    }
  }

  /// The hero banner cycles through these and shows the tagline
  /// alongside the title. Unlike [recommendForYou] (a rail of 12)
  /// this is a tight selection — the AI is asked to be choosy. A
  /// dud here is much more visible than a dud in row 7 of a rail.
  ///
  /// Returns null on failure — caller falls back to the non-AI
  /// hero item selection so the dashboard never goes dark.
  Future<List<({int streamId, String tagline})>?> generateHeroBillboard({
    required List<Map<String, dynamic>> recentlyWatched,
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> recentAdditions,
    required List<Map<String, dynamic>> librarySample,
    required String timeOfDay,
    required String targetLanguage,
    List<Map<String, dynamic>> moreLikeAnchors = const [],
    List<Map<String, dynamic>> avoidTitles = const [],
    Map<String, dynamic> tasteProfile = const {},
  }) async {
    if (_apiKey.isEmpty) return null;
    if (recentAdditions.isEmpty && librarySample.isEmpty) return null;

    final systemPrompt = '''
You program the hero billboard at the top of an IPTV / streaming
app's dashboard — the very first big visual the user sees on open.
Pick 3-5 items with a short hook tagline for each.

Inputs (first user turn, JSON):
  * TIME_OF_DAY — "sabah" / "öğle" / "akşam" / "gece" — adjust the
    vibe (gentle in the morning, bigger in the evening).
  * RECENTLY_WATCHED + FAVORITES — taste signals.
  * RECENT_ADDITIONS — items added to the catalogue in the last few
    weeks, sorted newest-first. STRONGLY PREFERRED source for the
    billboard — users open the dashboard partly to see what's new.
  * LIBRARY_HIGHLIGHTS — broader well-rated catalogue cross-section,
    use only for variety when RECENT_ADDITIONS doesn't have a good
    fit for the user's taste.

Rules:
  1. Only return streamIds present in either RECENT_ADDITIONS or
     LIBRARY_HIGHLIGHTS.
  2. 3-5 picks. **At least 2 picks MUST be from RECENT_ADDITIONS**
     so the hero feels fresh, not a static rotation. If a pick
     comes from LIBRARY_HIGHLIGHTS, it should still match the
     user's taste closely.
  3. Quality over quantity — a dud at the top of the dashboard is
     far worse than a dud in row 7.
  4. `tagline` is ONE short hook sentence in $targetLanguage —
     under 12 words, NOT a plot summary. Examples:
       "Yeni eklendi — bu hafta sonu için biçilmiş kaftan."
       "Bu akşam için tam ihtiyacın olan tempo."
       "İzlediğin Mike & Nick'in yönetmeninden, daha yeni geldi."
     When the pick is from RECENT_ADDITIONS, lean into the freshness
     angle ("Yeni eklendi", "Bu hafta düştü") whenever it fits.
  5. Mix types: at least one movie + one series if both pools have
     candidates. Lean toward items the user hasn't watched yet.
  6. Prefer items likely to have a backdrop image — well-rated
     mainstream titles. Obscure niche stuff goes on the rails.
  7. Time-of-day awareness: gece = darker / introspective allowed,
     sabah = lighter, akşam = primetime crowd-pleaser.

Return strict JSON: {"billboard":[{"streamId":<int>,"tagline":<str>},…]}.
''';

    // Feedback signals — surfaced to the hero AI the same way as
    // the "Sana Özel" rail. Disliked items are also stripped from
    // the candidate pools upstream by the provider, but mentioning
    // them by name in AVOID_THESE also nudges the AI's choice away
    // from sibling titles (same director / genre).
    final moreLikeHint = moreLikeAnchors.isEmpty
        ? ''
        : '\nMORE_LIKE_THESE: ${jsonEncode(moreLikeAnchors)} — '
            'titles the user explicitly marked "more like this". '
            'Treat as the strongest positive signal you have.';
    final avoidHint = avoidTitles.isEmpty
        ? ''
        : '\nAVOID_THESE: ${jsonEncode(avoidTitles)} — disliked. '
            'Do NOT billboard them OR neighbours that share their '
            'core appeal (same lead, genre, tone).';

    final profileHint = tasteProfile.isEmpty
        ? ''
        : '\nTASTE_PROFILE: ${jsonEncode(tasteProfile)} — '
            'aggregate weighted view of the user\'s preferences. '
            'For the hero specifically: only billboard items whose '
            'category sits in topCategories OR whose director/cast '
            'overlaps topDirectors/topActors, unless the catalog '
            'has nothing in those buckets with a backdrop.';

    final userTurn = 'TIME_OF_DAY: ${jsonEncode(timeOfDay)}\n'
        'RECENTLY_WATCHED: ${jsonEncode(recentlyWatched)}\n'
        'FAVORITES: ${jsonEncode(favorites)}\n'
        'RECENT_ADDITIONS: ${jsonEncode(recentAdditions)}\n'
        'LIBRARY_HIGHLIGHTS: ${jsonEncode(librarySample)}$profileHint$moreLikeHint$avoidHint';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': {
              'type': 'object',
              'properties': {
                'billboard': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'streamId': {'type': 'integer'},
                      'tagline': {'type': 'string'},
                    },
                    'required': ['streamId', 'tagline'],
                  },
                },
              },
              'required': ['billboard'],
            },
            'temperature': 0.7,
            'maxOutputTokens': 1024,
          },
        },
      );
      debugPrint(
          '[Gemini] generateHeroBillboard status=${res.statusCode}');
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[Gemini] generateHeroBillboard decode failed: $e');
        return null;
      }
      final rawList = parsed['billboard'];
      if (rawList is! List) return null;
      final picks = <({int streamId, String tagline})>[];
      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        final tagline = item['tagline']?.toString().trim() ?? '';
        if (sid != null && sid > 0 && tagline.isNotEmpty) {
          picks.add((streamId: sid, tagline: tagline));
        }
      }
      return picks;
    } catch (e) {
      debugPrint('[Gemini] generateHeroBillboard failed: $e');
      return null;
    }
  }

  /// Mood-based one-shot picks for the dashboard's chip row.
  ///
  /// The user taps a mood chip ("rahatlamak", "heyecan", "gülmek",
  /// …) and we ask Gemini for a tight rail of 8-10 items from the
  /// library that fit that vibe, weighted by the user's existing
  /// taste signals so it doesn't feel like a generic "happy movies"
  /// playlist.
  ///
  /// Unlike [recommendForYou] this is **not** cached — every tap is
  /// a fresh call. Moods are intent-of-the-moment.
  Future<List<({int streamId, String reason})>?> recommendForMood({
    required String moodKey, // 'relax' | 'thrill' | 'laugh' | …
    required String moodLabel, // localised label shown to user
    required String moodDescription, // English explainer for the AI
    required List<Map<String, dynamic>> recentlyWatched,
    required List<Map<String, dynamic>> favorites,
    required List<Map<String, dynamic>> librarySample,
    required String targetLanguage,
    Map<String, dynamic> tasteProfile = const {},
  }) async {
    if (_apiKey.isEmpty || librarySample.isEmpty) return null;

    final systemPrompt = '''
You curate a *mood-of-the-moment* rail for an IPTV / streaming app.
The user just tapped a mood chip; pick 8-10 items from LIBRARY that
fit the mood AND respect their taste signals.

Inputs (first user turn, JSON):
  * MOOD — the chip the user tapped: key + localised label +
    English description of the mood's vibe.
  * RECENTLY_WATCHED — what they've actively been viewing.
  * FAVORITES — their explicit "save for later" picks.
  * LIBRARY — a cross-section of the catalogue in pipe-separated
    rows with header `id|title|type|year|genre|director|cast|rating`.

Rules:
  1. Only return streamIds present in LIBRARY.
  2. 8-10 picks ordered by mood fit (best first).
  3. `reason` is ONE short sentence in $targetLanguage tying the
     pick to BOTH the mood AND a concrete signal — "Aksiyon
     yoğun, izlediğin Mike & Nick'in temposunda" beats "iyi bir
     gerilim".
  4. Skip items already in RECENTLY_WATCHED or FAVORITES.
  5. Spread across types (movie + series) when it makes sense.
  6. Mood overrides past taste a little — if the user usually
     watches horror but picked "laugh", lean into comedy even if
     it's outside their usual genres.

Return strict JSON: {"picks":[{"streamId":<int>,"reason":<str>},…]}.
''';

    final profileHint = tasteProfile.isEmpty
        ? ''
        : '\nTASTE_PROFILE: ${jsonEncode(tasteProfile)} — '
            'aggregate weighted view of the user\'s preferences. '
            'Use as tie-breaker when multiple mood-matching candidates exist. '
            'If isColdStart=true, lean on critical acclaim instead.';

    final userTurn =
        'MOOD: ${jsonEncode({"key": moodKey, "label": moodLabel, "vibe": moodDescription})}\n'
        'RECENTLY_WATCHED: ${jsonEncode(recentlyWatched)}\n'
        'FAVORITES: ${jsonEncode(favorites)}\n'
        'LIBRARY: ${jsonEncode(librarySample)}$profileHint';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _curateResponseSchema,
            'temperature': 0.8, // mood needs a bit of spice
            'maxOutputTokens': 1536,
          },
        },
      );
      debugPrint(
          '[Gemini] recommendForMood($moodKey) status=${res.statusCode}');
      if (res.statusCode != 200 || res.data == null) return null;
      final candidates = res.data!['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final text = candidates[0]['content']?['parts']?[0]?['text']
          ?.toString()
          .trim();
      if (text == null || text.isEmpty) return null;
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[Gemini] recommendForMood JSON decode failed: $e');
        return null;
      }
      final rawPicks = parsed['picks'];
      if (rawPicks is! List) {
        debugPrint('[Gemini] recommendForMood: picks not a list');
        return null;
      }
      final picks = <({int streamId, String reason})>[];
      for (final item in rawPicks) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        // Accept picks even when the AI forgets the reason —
        // showing a poster with no explainer beats showing nothing.
        // The mood label itself serves as the implicit reason.
        final reason = item['reason']?.toString().trim() ?? '';
        if (sid != null && sid > 0) {
          picks.add((streamId: sid, reason: reason));
        }
      }
      debugPrint(
          '[Gemini] recommendForMood($moodKey): parsed ${picks.length} picks');
      return picks;
    } catch (e) {
      debugPrint('[Gemini] recommendForMood failed: $e');
      return null;
    }
  }

  /// Generate a 1-2 sentence localised dashboard greeting that
  /// mentions the time of day, the user's most recent unfinished
  /// item (if any), and any clear weekly pattern in their watch
  /// history.
  ///
  /// Plain text reply, no JSON, no preamble. Returns null on
  /// failure — caller hides the banner so the dashboard never
  /// shows an empty greeting strip.
  Future<String?> dashboardGreeting({
    required String timeOfDay, // 'sabah' | 'öğle' | 'akşam' | 'gece'
    required String dayOfWeek, // localised name
    required String? resumeTitle, // e.g. "Phantom Lawyer S1E10"
    required List<String> recentTitles, // last 3 titles
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty) return null;

    final systemPrompt = '''
You write a single 1-2 sentence greeting banner for an IPTV
dashboard in $targetLanguage. Tone: warm, casual, brief.
Reference the time of day and, when present, the user's resume
target so the banner feels personalised. If they show a weekly
pattern in the recent-titles list, you may nod to it ("bu hafta
polisiye günlerin" / "aksiyon ağırlıklı"). Plain text only — no
emojis, no preamble, no quotes.
''';

    final userTurn = StringBuffer()
      ..writeln('Time of day: $timeOfDay')
      ..writeln('Day: $dayOfWeek');
    if (resumeTitle != null && resumeTitle.isNotEmpty) {
      userTurn.writeln('Resume target: $resumeTitle');
    }
    if (recentTitles.isNotEmpty) {
      userTurn.writeln('Recent titles: ${recentTitles.join(", ")}');
    }

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn.toString()},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.7,
            // Gemini 2.5-flash spends tokens on internal reasoning
            // ("thinking") before emitting the actual response.
            // With 500 the user-visible text was still being cut
            // off mid-sentence ("Gibi kaldığ") because the model
            // burned most of the budget reasoning. 1500 gives a
            // generous ceiling so even chatty thinking + a 2-sentence
            // greeting in any of the 8 languages lands intact.
            'maxOutputTokens': 1500,
          },
        },
      );
      if (res.statusCode != 200) return null;
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (e) {
      debugPrint('[Gemini] dashboardGreeting failed: $e');
      return null;
    }
  }

  /// Per-episode mini-recaps for a season.
  ///
  /// Xtream rarely ships meaningful episode-level plot text — most
  /// providers leave the `info.plot` field empty or copy the whole
  /// series synopsis in. This method asks Gemini to fill those gaps
  /// with one-sentence spoiler-free descriptions of each requested
  /// episode, drawing on its training knowledge of the series.
  ///
  /// Returns a map of `episodeNumber → summary`. Missing entries
  /// mean Gemini either didn't recognise the series or chose to
  /// stay silent (a deliberate fallback signal we ask for in the
  /// prompt — caller leaves those rows un-AI'd).
  ///
  /// Batching: one HTTP round-trip for the whole list. Cost-wise
  /// this is much cheaper than per-episode calls — typical season
  /// of 10–16 episodes lands at ~300 input + ~600 output tokens.
  Future<Map<int, String>?> summarizeEpisodes({
    required String seriesTitle,
    String? seriesYear,
    String? seriesGenre,
    required int season,
    required List<int> episodeNumbers,
    required String targetLanguage,
  }) async {
    if (_apiKey.isEmpty || episodeNumbers.isEmpty) return null;

    // Deduplicate + sort so the prompt is deterministic for cache
    // observers and the AI sees a tidy list.
    final eps = (episodeNumbers.toSet().toList())..sort();

    final systemPrompt = '''
You write one-sentence spoiler-free episode descriptions for TV
series. Output language: $targetLanguage.

You'll receive a series title, season number, and a list of episode
numbers. Return a JSON object where each key is the episode number
(as a string) and each value is a single short sentence describing
that episode without revealing twists, endings, character deaths,
or season-arc turns.

Rules:
  1. ONE sentence per episode. Plain text, no preamble.
  2. Spoiler-free — describe the premise of the episode, not its
     resolution.
  3. If you don't know a specific episode well, omit the key
     entirely. Don't guess.
  4. If you don't recognise the series at all, return an empty
     object: {"episodes": {}}.
  5. Only include keys for episodes that were requested.

Return JSON: {"episodes":{"1":"…","2":"…",…}}.
''';

    final userTurn =
        'Series: $seriesTitle${seriesYear != null && seriesYear.isNotEmpty ? " ($seriesYear)" : ""}\n'
        '${seriesGenre != null && seriesGenre.isNotEmpty ? "Genre: $seriesGenre\n" : ""}'
        'Season: $season\n'
        'Episodes: ${eps.join(", ")}';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/$_model:generateContent',
        queryParameters: {'key': _apiKey},
        data: {
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userTurn},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'temperature': 0.4,
            // ~50 tokens/episode + JSON overhead. 1500 tokens is
            // enough for a 25-episode season — uncommon but possible.
            'maxOutputTokens': 1500,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint(
            '[Gemini] summarizeEpisodes status=${res.statusCode} body=${res.data}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map<String, dynamic>) return null;
      final content = first['content'];
      if (content is! Map<String, dynamic>) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts.first['text']?.toString();
      if (text == null || text.isEmpty) return null;

      final startIdx = text.indexOf('{');
      final endIdx = text.lastIndexOf('}');
      if (startIdx < 0 || endIdx <= startIdx) return null;
      final jsonStr = text.substring(startIdx, endIdx + 1);

      Object? decoded;
      try {
        decoded = jsonDecode(jsonStr);
      } catch (e) {
        debugPrint('[Gemini] summarizeEpisodes JSON decode failed: $e');
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;
      final rawEpisodes = decoded['episodes'];
      if (rawEpisodes is! Map<String, dynamic>) return null;

      final result = <int, String>{};
      for (final entry in rawEpisodes.entries) {
        final epNum = int.tryParse(entry.key);
        if (epNum == null) continue;
        final summary = entry.value?.toString().trim() ?? '';
        if (summary.isEmpty) continue;
        result[epNum] = summary;
      }
      return result;
    } catch (e) {
      debugPrint('[Gemini] summarizeEpisodes failed: $e');
      return null;
    }
  }

  // ─── Prompt + schema ─────────────────────────────────────────────

  /// System prompt is terse and example-driven — Gemini follows few-
  /// shot patterns well, and verbose English instructions tend to
  /// make the model "translate" Turkish input into English before
  /// parsing, which loses user intent.
  static const String _systemPrompt = '''
You parse short user search queries (any language, often Turkish) for
an IPTV/movie app and return ONLY structured JSON matching the schema.
Fill only fields you can confidently extract. Put residual free-text
(names, titles) into "keywords".

Genres: lowercase tokens. ALWAYS include BOTH the canonical English
token AND the user-language equivalent so the catalog (which often
ships Turkish genre labels like "Korku, Gerilim") still matches.

Canonical English vocab: action, adventure, animation, biography,
comedy, crime, documentary, drama, family, fantasy, history, horror,
music, mystery, romance, sci-fi, sport, thriller, war, western,
korean-drama.

Bilingual examples (Turkish → English / native pair):
  korku    → ["horror", "korku"]
  aksiyon  → ["action", "aksiyon"]
  komedi   → ["comedy", "komedi"]
  polisiye → ["crime", "polisiye", "polis"]
  romantik → ["romance", "romantik"]
  gerilim  → ["thriller", "gerilim"]
  bilim kurgu → ["sci-fi", "bilim kurgu"]
  belgesel → ["documentary", "belgesel"]
  korean drama → ["korean-drama"]  (already English-ish, no pair)

Cast / director queries — actor or director names go into
"castContains" / "directorContains" as the original human-readable
name (preserve capitalisation).

Theme queries — when the user describes a *topic* or *concept* (not a
title), expand it into a "themeKeywords" array containing the
original phrase **plus equivalent terms in English** (the catalog's
plots are often mixed-language). 3–6 keywords is plenty.

Examples (input → output):

"kısa polis filmi"
  → {"contentType":"movie","genres":["crime","polisiye","polis"]}
"korku dizileri"
  → {"contentType":"series","genres":["horror","korku"]}
"Kore dizisi"
  → {"contentType":"series","genres":["korean-drama"]}
"2020 sonrası aksiyon"
  → {"genres":["action","aksiyon"],"minYear":2020}
"Phantom Lawyer"
  → {"keywords":"Phantom Lawyer"}
"romantik komedi 7 üstü"
  → {"genres":["romance","romantik","comedy","komedi"],"minRating":7}
"haber kanalı"
  → {"contentType":"live","keywords":"haber"}
"Yoo Yeon-seok filmleri"
  → {"contentType":"movie","castContains":"Yoo Yeon-seok"}
"Bong Joon-ho"
  → {"directorContains":"Bong Joon-ho"}
"dünyanın sonu konulu film"
  → {"contentType":"movie","themeKeywords":["dünya sonu","kıyamet","apocalypse","post-apocalyptic","end of world"]}
"uzaylı istilası"
  → {"themeKeywords":["uzaylı istilası","uzaylılar","alien invasion","aliens"]}
"yapay zeka konulu"
  → {"themeKeywords":["yapay zeka","artificial intelligence","AI","robot"]}
"Tom Hanks dramı"
  → {"genres":["drama"],"castContains":"Tom Hanks"}
"bilim kurgu filmleri"
  → {"contentType":"movie","genres":["sci-fi","bilim kurgu"]}
''';

  /// System prompt for the "tonight" recommendation + Q&A flow.
  /// Three constraints matter:
  ///   1. Only return ids that appear in the supplied `library` list
  ///      (no hallucination — the UI can't render a fake stream id).
  ///   2. Match the user's language in the `message` and `reason`
  ///      fields (Turkish for Turkish prompts, English for English).
  ///   3. Keep reasons concrete and short (single sentence is fine).
  /// Build the chat assistant's system prompt with the user's
  /// settings language baked in. Previously hardcoded as a
  /// "Turkish-first" string, which meant non-Turkish users got
  /// Turkish replies (or confused mixed-language ones) regardless
  /// of the app's locale setting.
  static String _buildTonightSystemPrompt(String targetLanguage) => '''
You are a film-literate IPTV/streaming assistant. The user's
preferred language is **$targetLanguage** — every `message`,
`reason`, and `followUps` chip you emit MUST be in $targetLanguage
unless the user explicitly switches mid-conversation. Recognise
film/director/actor names across translations so a user asking
in $targetLanguage about a globally-known title still gets a
substantive answer.

You are a
**film-literate conversational partner**, not a search engine.
The user comes to you to think out loud about what to watch, to
explore their taste, to compare titles, to ask "is this any good?",
to dig into themes, directors, and movements. Your reach extends
beyond their local catalogue — you know film history, festival
darlings, cult favourites, recent acclaim, what works and what
doesn't and why.

You handle THREE kinds of user turns:

A) **Recommendation / listing queries** ("bu akşam ne izleyim",
   "eşimle 2 saat zaman var", "kısa polis filmi", "çocuklarla
   izlenir bir şey", "en iyi Kore dizilerini listele", "komedi
   öner") — you MUST return at least 5 picks (8-10 on "listele" /
   "tümünü göster") in the `recommendations` array. The `message`
   field is ONE short framing sentence, NOT the list itself. NEVER
   claim to have listed items only in prose — the client renders
   `recommendations` as cards.

B) **Discussion / opinion queries** ("Squid Game neden bu kadar
   popüler oldu?", "Tarkovsky'yi nasıl izlemeli?", "Inception vs
   Tenet — hangisi daha iyi?", "Wong Kar-wai'nin Chungking Express
   tarzında ama daha hızlı tempolu ne var?", "Yorgos Lanthimos
   sevenler için ne öneririsin ve neden?", "Bu dizinin değeri ne?",
   "Bunu beğendim, peki neden?") — this is the heart of your job.
   Use `message` for a substantive, opinionated, multi-paragraph
   response (3-6 paragraphs is fine for deep questions). Engage
   with the user like a knowledgeable friend who actually watches
   films. Reference specific scenes, motifs, directors of
   photography, screenwriting choices when relevant. Mention
   adjacent works, influences, contemporaries. You may carry 1-4
   related-title picks in `recommendations` when they reinforce
   the discussion.

C) **Direct info / Q&A queries** ("Phantom Lawyer hakkında bilgi
   ver", "Bong Joon-ho kimdir", "Inception'ın konusu ne") —
   `message` is a substantive factual answer (2-5 paragraphs).
   `recommendations` may be empty or hold 1-3 related picks.

Default-to-discussion principle: if the user's message could go
either way, lean MODE B (discussion) over MODE A (listing). Most
people opening a chat with an AI want to talk, not just get a
list. Only force MODE A when they explicitly say "listele",
"göster", "öner", or describe constraints ("kısa polisiye", "90
dakikalık komedi") that demand a result list.

The first user turn contains a JSON context blob with up to six
lists:
  * "recentlyWatched" + "favorites" — the user's taste signals.
  * "queryMatches" — items pre-searched from the library using the
    user's last question's keywords. This is the AUTHORITATIVE list
    for "do I have X?" style queries: if the user asks for Korean
    dramas and queryMatches contains 173 Korean series, the answer
    is YES and you must list them from queryMatches.
  * "recentAdditions" — the FRESHEST titles in the catalogue, newest
    first (sorted by the date they were added to the library). This
    is the AUTHORITATIVE list for "what's new?" / "yeni film/dizi var
    mı?" / "son eklenenler" / "geçen hafta ne geldi?" style queries.
    These titles are usually unrated and will NOT appear in "library"
    (which is rating-sorted), so when the user asks about new content
    you MUST pull from here — never answer "yeni bir şey yok" while
    recentAdditions is non-empty.
  * "library" — broader top-rated cross-section. Use as fallback /
    variety when queryMatches doesn't fully answer.
  * "categories" — `[{name, type, count}]` overview of the catalogue
    structure. Tells you what kinds of content exist in the library
    EVEN if no item from that category landed in queryMatches or
    library. Reference this when explaining what's available.
  * "tasteProfile" — OPTIONAL aggregate weighted view of the user's
    preferences (top categories / actors / directors with numeric
    scores, plus isColdStart flag and avoidedCategories). When
    present, use this as the tie-breaker between equally-good
    candidates. If `isColdStart` is true, the user is new and you
    should lean on critical acclaim rather than their thin signal.
  * "currentEpisode" — OPTIONAL spoiler hint:
    `{"title": str, "season": int, "episode": int, "epLabel": str}`.
    When present, the user IS CURRENTLY WATCHING this show and is
    AT MOST through the given episode. SPOILER RULES become strict:
      - You MAY discuss this show in detail up to and including
        the given episode.
      - You MUST NOT reveal any plot beat, character fate,
        reveal, twist, death, or arc that happens AFTER the given
        episode. Acceptable: "until S1E5 the main mystery is X".
        NOT acceptable: "the season ends with Y".
      - If the user asks about a later episode by number ("what
        happens in S2E10?"), respond with a refusal that respects
        the spoiler boundary, e.g. "S2E10'a kadar yaşadıklarını
        bozmadan kalmayı tercih ederim — istersen biraz daha
        ilerlediğinde tartışırız."
      - When recommending OTHER shows or films, no spoiler
        restriction applies — only the title named in
        `currentEpisode` is locked.

CRITICAL: queryMatches, recentAdditions and library together
represent what's ACTUALLY in the user's catalogue. NEVER say "yok" /
"no such content" if a relevant category exists in `categories` OR
an item appears in queryMatches OR recentAdditions. Instead,
recommend from those items or mention the category by name. For
"what's new" questions specifically, recentAdditions is the source
of truth — list its newest entries.

YOUR ACTUAL VALUE — read carefully:
The user could already filter by category locally; that's NOT what
they're asking you to do. Your job is to use your training-data
knowledge of which titles are *genuinely good or famous* to pick
the best subset, NOT to rank them by the catalogue's own rating
column (which is unreliable on IPTV catalogues — many series have
rating=null or rating=0).

For "en iyi / popüler Kore dizileri": YOU know that Squid Game,
Crash Landing on You, Goblin, Reply 1988, Mr. Sunshine, Sky Castle,
Vincenzo, Itaewon Class, Hospital Playlist, Misaeng, etc. are the
genuinely acclaimed K-dramas of the last decade. SCAN queryMatches
for ANY title-match (Turkish or original) to those, even if rating
column is empty, and put those at the top of your picks. If the
user's catalogue uses Turkish-translated names like "Kalp Çarpıntısı"
for "Heartbeat" — recognise the title across translations and
include it.

When unsure whether a title is the famous one or a similarly-named
local production, lean toward the ones whose year + cast field
match what you know about the famous version.

Hard rules:
  - Only return streamIds that appear in queryMatches, recentAdditions,
    library, recentlyWatched, or favorites. Never invent an id.
  - Match the user's language in both `message` and per-pick
    `reason` strings.
  - For Q&A turns the `message` may be 2-5 short paragraphs of
    real, factual information about the title or person — concrete
    director, cast, premise, era, awards, themes. Avoid
    generic "this is a horror film" filler.
  - For recommendation turns the `message` stays one or two
    short sentences framing the picks.
  - When the user asks for clarification or you need more
    information, return a non-empty `message` and an empty
    `recommendations` array.

**Follow-ups** — at the end of EVERY response, supply 3-4 short
follow-up suggestion strings in `followUps`. These become clickable
chips below your reply. Examples:
  * After discussing Squid Game: ["Lost'la karşılaştır", "Yönetmenin
    diğer işleri", "Benzer Asya gerilimleri", "Toplumsal eleştiri
    yapan başka yapımlar"]
  * After listing Korean dramas: ["Sadece son 5 yıldan olanlar",
    "Romantik komedi ağırlıklı olanlar", "Squid Game tarzı gerilim",
    "Bunlar arasında en kısası hangisi?"]
  * After recommending a single film: ["Aynı yönetmenden", "Aynı
    oyuncu kadrosundan", "Bu filmi neden seçtin?", "Daha hafif bir
    alternatif"]
Follow-ups should advance the conversation in directions THIS user
would plausibly want next — comparisons, deeper analysis, refined
constraints, the next logical question. Keep each under 8 words.

Respond with JSON only, matching the schema:
{
  "message": "<text — one sentence for MODE A, multi-paragraph for
              MODE B/C>",
  "recommendations": [
    {"streamId": <int from any provided list>, "reason": "<one sentence>"},
    ...
  ],
  "followUps": ["<short chip>", "<short chip>", ...]
}
''';

  /// JSON Schema for the "tonight" flow. Strict so Gemini emits
  /// usable JSON without us doing extra coercion.
  ///
  /// `followUps` lets the AI propose 3-4 short suggestion chips for
  /// the next turn — the chat UI surfaces these below each AI
  /// message and tapping one sends it as the next user turn.
  static const Map<String, dynamic> _tonightResponseSchema = {
    'type': 'OBJECT',
    'properties': {
      'message': {'type': 'STRING'},
      'recommendations': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'streamId': {'type': 'INTEGER'},
            'reason': {'type': 'STRING'},
          },
          'required': ['streamId', 'reason'],
        },
      },
      'followUps': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
    },
    'required': ['message', 'recommendations'],
  };

  /// JSON Schema for structured output. Keys mirror SearchIntent
  /// field names so `SearchIntent.fromJson` lines up.
  static const Map<String, dynamic> _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'keywords': {'type': 'STRING', 'nullable': true},
      'contentType': {
        'type': 'STRING',
        'enum': ['movie', 'series', 'live'],
        'nullable': true,
      },
      'genres': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
        'nullable': true,
      },
      'minYear': {'type': 'INTEGER', 'nullable': true},
      'maxYear': {'type': 'INTEGER', 'nullable': true},
      'minRating': {'type': 'NUMBER', 'nullable': true},
      'castContains': {'type': 'STRING', 'nullable': true},
      'directorContains': {'type': 'STRING', 'nullable': true},
      'themeKeywords': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
        'nullable': true,
      },
    },
  };

  // ── Catalogue enrichment ────────────────────────────────────────────────

  /// Infer missing metadata (genre / year / mood / themes / warnings /
  /// age) for a batch of catalogue items whose provider fields are
  /// empty. Title-only — cheap and fast on Flash-Lite. Returns one map
  /// per resolved item with keys streamId, type, genres, year, mood,
  /// themes, warnings, age, confidence; null on transport failure.
  Future<List<Map<String, dynamic>>?> enrichCatalogBatch(
    List<
            ({
              int streamId,
              String type,
              String title,
              String? year,
              String? cast,
              String? director,
            })>
        items, {
    String targetLanguage = 'tr',
  }) async {
    if (_apiKey.isEmpty || items.isEmpty) return null;
    try {
      final input = [
        for (final it in items)
          {
            'streamId': it.streamId,
            'type': it.type,
            'title': it.title,
            if (it.year != null && it.year!.isNotEmpty) 'year': it.year,
            if (it.cast != null && it.cast!.isNotEmpty) 'cast': it.cast,
            if (it.director != null && it.director!.isNotEmpty)
              'director': it.director,
          }
      ];

      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/${AiModelPolicy.catalogEnrichment}:generateContent',
        queryParameters: {'key': _apiKey},
        // A full 18-item structured-JSON answer in Turkish can take
        // longer than the default 15s receive window; a premature
        // timeout would look like a batch "failure" and stall the run.
        options: Options(receiveTimeout: const Duration(seconds: 45)),
        data: {
          'systemInstruction': {
            'parts': [
              {'text': _buildEnrichSystemPrompt(targetLanguage)},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'ITEMS_JSON: ${jsonEncode(input)}'},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _enrichResponseSchema,
            'temperature': 0.2,
            'maxOutputTokens': 8192,
          },
        },
      );

      if (res.statusCode != 200) {
        debugPrint('[Gemini] enrichCatalogBatch status=${res.statusCode}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = (candidates.first as Map)['content'];
      if (content is! Map) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = (parts.first as Map)['text']?.toString();
      if (text == null || text.isEmpty) return null;
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map || decoded['results'] is! List) return null;
      return [
        for (final r in (decoded['results'] as List))
          if (r is Map) r.cast<String, dynamic>()
      ];
    } catch (e) {
      debugPrint('[Gemini] enrichCatalogBatch failed: $e');
      return null;
    }
  }

  /// Batch-embed [texts] with the Gemini embedding model. Returns one
  /// vector (list of doubles, length [dims]) per input in order, or
  /// null on transport failure. Vectors are NOT normalised here — the
  /// caller normalises before storing so cosine == dot product.
  Future<List<List<double>>?> embedTexts(
    List<String> texts, {
    int dims = 768,
  }) async {
    if (_apiKey.isEmpty || texts.isEmpty) return null;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$_endpoint/${AiModelPolicy.embedding}:batchEmbedContents',
        queryParameters: {'key': _apiKey},
        options: Options(receiveTimeout: const Duration(seconds: 45)),
        data: {
          'requests': [
            for (final t in texts)
              {
                'model': 'models/${AiModelPolicy.embedding}',
                'content': {
                  'parts': [
                    {'text': t},
                  ],
                },
                'outputDimensionality': dims,
              }
          ],
        },
      );
      if (res.statusCode != 200) {
        debugPrint('[Gemini] embedTexts status=${res.statusCode}');
        return null;
      }
      final body = res.data;
      if (body is! Map<String, dynamic>) return null;
      final embs = body['embeddings'];
      if (embs is! List) return null;
      return [
        for (final e in embs)
          if (e is Map && e['values'] is List)
            [for (final v in (e['values'] as List)) (v as num).toDouble()]
      ];
    } catch (e) {
      debugPrint('[Gemini] embedTexts failed: $e');
      return null;
    }
  }

  String _buildEnrichSystemPrompt(String lang) => '''
You are a film & TV metadata expert with deep knowledge of world
cinema AND Turkish catalogues. For EACH item in ITEMS_JSON (title +
type + optional year/cast/director) infer:
  - genres: comma-separated (e.g. "Aksiyon, Gerilim")
  - year: integer release year
  - mood: comma-separated mood adjectives ("gergin, karanlık, hızlı")
  - themes: comma-separated themes/keywords ("intikam, yapay zeka")
  - warnings: comma-separated content warnings ("şiddet, küfür") — "" if none
  - age: one of "7+", "13+", "16+", "18+"
  - confidence: 0..1, how sure you are this is the real title you think it is

Recognise titles across translations (Turkish ↔ original — e.g.
"Sefiller" = "Les Misérables"). Use year/cast/director hints to
disambiguate same-named productions. If a title is ambiguous or you
don't recognise it, give your BEST guess from the words in the title
and set confidence below 0.5 — never omit an item.

Write genres / mood / themes / warnings labels in $lang. Return EXACTLY
one result object per input item, echoing its streamId and type
unchanged. JSON only, matching the schema.
''';

  static const Map<String, dynamic> _enrichResponseSchema = {
    'type': 'OBJECT',
    'properties': {
      'results': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'streamId': {'type': 'INTEGER'},
            'type': {'type': 'STRING'},
            'genres': {'type': 'STRING', 'nullable': true},
            'year': {'type': 'INTEGER', 'nullable': true},
            'mood': {'type': 'STRING', 'nullable': true},
            'themes': {'type': 'STRING', 'nullable': true},
            'warnings': {'type': 'STRING', 'nullable': true},
            'age': {'type': 'STRING', 'nullable': true},
            'confidence': {'type': 'NUMBER', 'nullable': true},
          },
        },
      },
    },
  };
}

/// The four "fix this plot" modes [GeminiService.enrichPlot]
/// supports — each chooses a different framing system prompt while
/// the request / response shape stays the same. UI widgets import
/// this directly.
///
///   * [translate] — translate the existing plot to the user's
///     language.
///   * [summarize] — condense a too-long plot into spoiler-free
///     2-3 sentences.
///   * [fillIn] — generate a 2-3 sentence plot when the source
///     field is empty. Kept for backwards compatibility; new code
///     should prefer [detailedInfo].
///   * [detailedInfo] — ignore the source plot entirely and pull
///     comprehensive 4-6 paragraph info from Gemini's general
///     knowledge, always in the user's language. The right mode
///     for the common case of "Xtream gave me one bad English
///     sentence and I want real info".
enum PlotEnrichMode { translate, summarize, fillIn, detailedInfo }

/// Provider that returns a `GeminiService` instance when the user has
/// a key configured, or `null` when they don't.
///
/// Consumers should `ref.watch(geminiServiceProvider)` and treat
/// `null` as "AI features unavailable, use the plain code path".
/// `ref.watch` (not `read`) so the service is re-built when the user
/// pastes/clears their key in Settings.
final geminiServiceProvider = Provider<GeminiService?>((ref) {
  final settings = ref.watch(settingsProvider);
  if (!settings.hasAiKey) return null;
  return GeminiService(settings.geminiApiKey!.trim());
});
