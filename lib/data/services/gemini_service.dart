import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/models/search_intent.dart';
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
  }) async {
    if (_apiKey.isEmpty || conversation.isEmpty) return null;

    try {
      // Compact each channel into the smallest informative form the
      // model needs. Skipping `plot` keeps the prompt small; the AI
      // gets to pick from the sample by id and the UI looks up the
      // full row to render. We *do* keep genre/year/rating because
      // they're the levers the AI needs to reason about fit.
      Map<String, dynamic> compact(Channel ch) => {
            'id': ch.streamId,
            'title': ch.name,
            'type': ch.type,
            if (ch.genre != null && ch.genre!.isNotEmpty) 'genre': ch.genre,
            if (ch.year != null && ch.year!.isNotEmpty) 'year': ch.year,
            if (ch.rating != null) 'rating': ch.rating,
          };

      final contextBlob = {
        'recentlyWatched': recentlyWatched.map(compact).toList(),
        'favorites': favorites.map(compact).toList(),
        'library': librarySample.map(compact).toList(),
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
              {'text': _tonightSystemPrompt},
            ],
          },
          'contents': contents,
          'generationConfig': {
            'responseMimeType': 'application/json',
            'responseSchema': _tonightResponseSchema,
            'temperature': 0.7, // some warmth in phrasing
            'maxOutputTokens': 1024,
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

  /// Three "fix this plot" use-cases the detail page wires to small
  /// inline links underneath the synopsis text. Each maps to a
  /// different system prompt — the user-visible action stays the
  /// same shape ("ask Gemini → swap the text"), only the framing
  /// differs.
  ///
  /// Returns the AI-produced plot text, or `null` on any failure.
  /// Caller falls back to keeping the original.
  Future<String?> enrichPlot({
    required String title,
    String? year,
    String? genre,
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
Generate a 2–3 sentence plot description based on what's
generally known about the title. Reply in the user's language
($targetLanguage), plain text, no preamble, no disclaimers. If
you genuinely don't recognise the title, reply with the single
word "UNKNOWN" (uppercase, no punctuation) — caller drops the
result in that case.
''',
      PlotEnrichMode.detailedInfo => '''
The user wants comprehensive information about this title, in
their language ($targetLanguage). The plot field they currently
see is unreliable (often machine-translated, truncated, or in
the wrong language) — write a richer description from your
general knowledge of the title instead.

Cover these in 4–6 short paragraphs, separated by blank lines:
  1. Premise — what's the setup, who's the protagonist
  2. Tone & style — pace, atmosphere, signature elements
  3. Themes — what the story is really *about*
  4. Why it stands out — what's notable (awards, director,
     cultural impact, unique angle)
  5. Recommended viewer — who'll enjoy this most

Spoiler-free. No reveals, no ending hints, no twists. Plain text
with paragraph breaks (use blank lines between paragraphs). No
markdown headings, no preamble, no "Here's the info:" framing.

If you genuinely don't recognise the title with confidence, reply
with the single word "UNKNOWN" (uppercase, no punctuation) —
caller drops the result.
''',
    };

    final userTurn = switch (mode) {
      PlotEnrichMode.translate ||
      PlotEnrichMode.summarize =>
        'Title: $title${year != null && year.isNotEmpty ? " ($year)" : ""}'
            '${genre != null && genre.isNotEmpty ? "\nGenre: $genre" : ""}'
            '\n\nPlot:\n${originalPlot ?? ""}',
      PlotEnrichMode.fillIn ||
      PlotEnrichMode.detailedInfo =>
        'Title: $title${year != null && year.isNotEmpty ? " ($year)" : ""}'
            '${genre != null && genre.isNotEmpty ? "\nGenre: $genre" : ""}',
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
            // detailedInfo needs a roomier budget — 4-6 short paragraphs
            // can comfortably exceed 400 tokens, and a truncated reply
            // looks worse than no reply at all.
            'maxOutputTokens':
                mode == PlotEnrichMode.detailedInfo ? 900 : 400,
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
      // Modes that can opt out with the UNKNOWN sentinel when the
      // model can't confidently describe the title. UI keeps the
      // original plot in that case.
      if ((mode == PlotEnrichMode.fillIn ||
              mode == PlotEnrichMode.detailedInfo) &&
          text.toUpperCase() == 'UNKNOWN') {
        return null;
      }
      return text;
    } catch (e) {
      debugPrint('[Gemini] enrichPlot failed: $e');
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

Use lowercase English genre names: action, adventure, animation,
biography, comedy, crime, documentary, drama, family, fantasy,
history, horror, music, mystery, romance, sci-fi, sport, thriller,
war, western, korean-drama.

Examples (input → output):

"kısa polis filmi" → {"contentType":"movie","genres":["crime"]}
"Kore dizisi" → {"contentType":"series","genres":["korean-drama"]}
"2020 sonrası aksiyon" → {"genres":["action"],"minYear":2020}
"Phantom Lawyer" → {"keywords":"Phantom Lawyer"}
"romantik komedi 7 üstü" → {"genres":["romance","comedy"],"minRating":7}
"haber kanalı" → {"contentType":"live","keywords":"haber"}
''';

  /// System prompt for the "tonight" recommendation flow. Three
  /// constraints matter:
  ///   1. Only return ids that appear in the supplied `library` list
  ///      (no hallucination — the UI can't render a fake stream id).
  ///   2. Match the user's language in the `message` and `reason`
  ///      fields (Turkish for Turkish prompts, English for English).
  ///   3. Keep reasons concrete and short (single sentence is fine).
  static const String _tonightSystemPrompt = '''
You are a Turkish-first IPTV/streaming recommendation assistant.

The first user turn contains a JSON context blob with three lists:
"recentlyWatched", "favorites", "library". Use these to understand
the user's taste and to pick recommendations *only from the library
list*. Do not invent stream ids or titles that aren't in the library.

Match the user's language in your replies. If the user writes
Turkish, answer Turkish.

Respond with JSON only, matching the schema:
{
  "message": "<one or two short sentences framing your picks>",
  "recommendations": [
    {"streamId": <int from library>, "reason": "<one sentence in user's language>"},
    ...
  ]
}

Aim for 3-5 recommendations. If the user asks a clarifying question
or you need more information, return a non-empty "message" and an
empty "recommendations" array. If absolutely nothing in the library
fits the request, return an empty array with a brief explanation in
"message".
''';

  /// JSON Schema for the "tonight" flow. Strict so Gemini emits
  /// usable JSON without us doing extra coercion.
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
