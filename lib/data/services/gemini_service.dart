import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/models/search_intent.dart';
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
