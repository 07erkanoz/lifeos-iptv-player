import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/services/ai_operation.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/data/models/tonight_recommendation.dart';

Map<String, dynamic> response(List<Map<String, dynamic>> parts) => {
  'candidates': [
    {
      'finishReason': 'STOP',
      'content': {'role': 'model', 'parts': parts},
    },
  ],
};
void main() {
  test(
    '3.8 uses header authentication and LOW without deprecated parameters',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, contains('/gemini-3.8-flash:generateContent'));
            expect(request.queryParameters, isEmpty);
            expect(request.headers['x-goog-api-key'], 'fixture-key');
            final config = (request.data as Map)['generationConfig'] as Map;
            expect(config.containsKey('temperature'), isFalse);
            expect(config['thinkingConfig'], {'thinkingLevel': 'LOW'});
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: response([
                  {'thought': true, 'text': 'private thought'},
                  {'text': '{"genres":'},
                  {'text': '["drama"]}'},
                ]),
              ),
            );
          },
        ),
      );
      final service = GeminiService('fixture-key', dio: dio);
      addTearDown(service.dispose);
      expect((await service.parseSearchQuery('drama'))?.genres, ['drama']);
    },
  );
  test(
    'tool IDs and thought signatures survive a subsequent user turn',
    () async {
      final dio = Dio();
      var requestNumber = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requestNumber++;
            final contents = (request.data as Map)['contents'] as List;
            if (requestNumber >= 2) {
              expect(contents.toString(), contains('fixture-signature'));
              expect(contents.toString(), contains('fixture-call'));
            }
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: response(
                  requestNumber == 1
                      ? [
                          {
                            'thoughtSignature': 'fixture-signature',
                            'functionCall': {
                              'id': 'fixture-call',
                              'name': 'searchLibrary',
                              'args': {'query': 'drama'},
                            },
                          },
                        ]
                      : [
                          {'text': 'Fixture answer'},
                        ],
                ),
              ),
            );
          },
        ),
      );
      final service = GeminiService('fixture-key', dio: dio);
      addTearDown(service.dispose);
      final session = GeminiAgentSession();
      final first = await service.runAgent(
        conversation: [(fromUser: true, text: 'First')],
        contextJson: '{}',
        targetLanguage: 'en',
        session: session,
        onToolCall: (_, _) async => {'results': []},
      );
      expect(first?.message, 'Fixture answer');
      await service.runAgent(
        conversation: [(fromUser: true, text: 'Second')],
        contextJson: '{}',
        targetLanguage: 'en',
        session: session,
        onToolCall: (_, _) async => {},
      );
      expect(requestNumber, 3);
    },
  );
  test('expired turn cannot execute a delayed tool', () async {
    final operation = AiOperation();
    final completed = Completer<void>();
    var mutated = false;
    final result = await operation.withDeadline<int>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      try {
        AiOperation.current!.checkActive();
        mutated = true;
      } finally {
        completed.complete();
      }
      return 1;
    }, const Duration(milliseconds: 5));
    expect(result, isNull);
    await completed.future;
    expect(mutated, isFalse);
  });
  test(
    'quota, blocked and truncated responses retain safe error codes',
    () async {
      for (final scenario in [
        ('quota', 429, <String, dynamic>{}),
        (
          'blocked',
          200,
          <String, dynamic>{
            'promptFeedback': {'blockReason': 'SAFETY'},
          },
        ),
        (
          'truncated',
          200,
          <String, dynamic>{
            'candidates': [
              {'finishReason': 'MAX_TOKENS'},
            ],
          },
        ),
      ]) {
        final dio = Dio();
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) => handler.resolve(
              Response(
                requestOptions: request,
                statusCode: scenario.$2,
                data: scenario.$3,
              ),
            ),
          ),
        );
        final service = GeminiService('fixture-key', dio: dio),
            operation = AiOperation();
        expect(
          await operation.run(() => service.parseSearchQuery('fixture')),
          isNull,
        );
        expect(operation.errorCode, scenario.$1);
        service.dispose();
      }
    },
  );
  test(
    'terminal parallel calls retain each actual response and its ID',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final names =
                ((request.data as Map)['tools'] as List)
                        .first['functionDeclarations']
                    as List;
            expect(names.any((d) => d['name'] == 'setReminder'), false);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: response([
                  {
                    'functionCall': {
                      'id': 'search-id',
                      'name': 'searchLibrary',
                      'args': {'query': 'drama'},
                    },
                  },
                  {
                    'functionCall': {
                      'id': 'answer-id',
                      'name': 'presentRecommendations',
                      'args': {'message': 'Found it', 'recommendations': []},
                    },
                  },
                ]),
              ),
            );
          },
        ),
      );
      final service = GeminiService('fixture-key', dio: dio),
          session = GeminiAgentSession();
      var executed = 0;
      final result = await service.runAgent(
        conversation: [(fromUser: true, text: 'Fixture')],
        contextJson: '{}',
        targetLanguage: 'en',
        session: session,
        allowReminders: false,
        onToolCall: (_, _) async {
          executed++;
          return {
            'results': ['actual-result'],
          };
        },
      );
      expect(result?.message, 'Found it');
      expect(executed, 1);
      final parts = session.contents.last['parts'] as List;
      expect(parts.first['functionResponse']['id'], 'search-id');
      expect(parts.first['functionResponse']['response']['results'], [
        'actual-result',
      ]);
      expect(parts.last['functionResponse']['id'], 'answer-id');
      service.dispose();
    },
  );
  test('typed recommendations preserve colliding IDs', () {
    final movie = TonightRecommendation.fromJson({
      'streamId': 42,
      'type': 'movie',
      'reason': 'Movie',
    })!;
    final series = TonightRecommendation.fromJson({
      'streamId': 42,
      'type': 'series',
      'reason': 'Series',
    })!;
    expect(movie.key, isNot(series.key));
    expect(
      TonightRecommendation.fromJson({
        'streamId': 42,
        'type': 'unknown',
        'reason': 'Fixture',
      }),
      isNull,
    );
  });
}
