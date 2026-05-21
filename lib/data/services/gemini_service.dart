import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
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
            // 2048 was 1024 — the Q&A path may produce a couple of
            // short paragraphs of real information, which a tighter
            // budget was truncating mid-sentence.
            'maxOutputTokens': 2048,
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
  static const String _tonightSystemPrompt = '''
You are a Turkish-first IPTV/streaming assistant. You handle TWO
kinds of user turns and adjust the response shape accordingly:

A) **Recommendation queries** ("bu akşam ne izleyim", "eşimle 2
   saat zaman var", "kısa polis filmi", "çocuklarla izlenir bir
   şey", "drama dışında öner") — return 3-5 picks from the
   library plus a short framing message.

B) **Direct info / Q&A queries** ("Phantom Lawyer hakkında bilgi
   ver", "Mad Max nedir", "Bong Joon-ho kimdir", "Inception'ın
   konusu ne") — use the `message` field for a substantive
   multi-paragraph answer in the user's language. Recommendations
   array can be empty, or carry 1-3 related-title picks if
   genuinely helpful.

The first user turn contains a JSON context blob with three lists
("recentlyWatched", "favorites", "library"). Use these for taste
context AND for resolving title references — if the user says
"Phantom Lawyer hakkında bilgi ver" and that title exists in the
library, prefer that streamId when picking a related title.

Hard rules:
  - Only return streamIds that appear in the library list.
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

Respond with JSON only, matching the schema:
{
  "message": "<plain text — short framing for picks, OR
              multi-paragraph answer for Q&A>",
  "recommendations": [
    {"streamId": <int from library>, "reason": "<one sentence>"},
    ...
  ]
}
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
      'castContains': {'type': 'STRING', 'nullable': true},
      'directorContains': {'type': 'STRING', 'nullable': true},
      'themeKeywords': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
        'nullable': true,
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
