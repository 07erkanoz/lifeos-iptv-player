import 'dart:async';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_enrichment_repository.dart';
import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';
import 'package:lifeostv/data/services/catalog_enrichment_runner.dart';
import 'package:lifeostv/data/services/catalog_embedding_runner.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/data/services/semantic_search_service.dart';

class _Gemini extends GeminiService {
  _Gemini() : super('test');
  int calls = 0;
  final started = Completer<void>();
  final result = Completer<List<Map<String, dynamic>>?>();
  final vectors = Completer<List<List<double>>?>();
  @override
  Future<List<Map<String, dynamic>>?> enrichCatalogBatch(
    List<
      ({
        int streamId,
        String type,
        String title,
        String? year,
        String? cast,
        String? director,
      })
    >
    items, {
    String targetLanguage = 'tr',
  }) {
    calls++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<List<List<double>>?> embedTexts(
    List<String> texts, {
    int dims = 768,
    bool retrievalQuery = false,
  }) {
    calls++;
    if (!started.isCompleted) started.complete();
    return vectors.future;
  }
}

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final type in ['movie', 'series']) {
      await db
          .into(db.channels)
          .insert(
            ChannelsCompanion.insert(
              streamId: 7,
              name: type,
              type: type,
              categoryId: 'test',
            ),
          );
    }
  });
  tearDown(() => db.close());
  test(
    'playback gate prevents starting enrichment and embedding HTTP',
    () async {
      final api = _Gemini();
      expect(
        await CatalogEnrichmentRunner(
          ContentEnrichmentRepository(db),
          api,
          'tr',
          shouldPause: () => true,
        ).runOnce(),
        0,
      );
      expect(
        await CatalogEmbeddingRunner(
          ContentEmbeddingsRepository(db),
          api,
          shouldPause: () => true,
        ).runOnce(),
        0,
      );
      expect(api.calls, 0);
    },
  );
  test(
    'playback starting during HTTP discards the pending enrichment result',
    () async {
      var playing = false;
      final api = _Gemini();
      final runner = CatalogEnrichmentRunner(
        ContentEnrichmentRepository(db),
        api,
        'tr',
        shouldPause: () => playing,
      );
      final work = runner.runOnce();
      await api.started.future;
      playing = true;
      api.result.complete([
        {'streamId': 7, 'type': 'movie', 'genres': 'Drama', 'confidence': .9},
      ]);
      expect(await work, 0);
      expect(await db.select(db.contentEnrichment).get(), isEmpty);
    },
  );
  test('disposed embedding runner cannot commit a late response', () async {
    await db
        .update(db.channels)
        .write(const ChannelsCompanion(genre: Value('Drama')));
    final api = _Gemini();
    final runner = CatalogEmbeddingRunner(
      ContentEmbeddingsRepository(db),
      api,
      shouldPause: () => false,
    );
    final work = runner.runOnce();
    await api.started.future;
    runner.cancel();
    api.vectors.complete([List.filled(768, 1), List.filled(768, 2)]);
    expect(await work, 0);
    expect(await db.select(db.contentEmbeddings).get(), isEmpty);
  });
  test(
    'typed validation rejects invented, duplicate and low-confidence metadata',
    () async {
      final api = _Gemini();
      api.result.complete([
        {'streamId': 7, 'type': 'live', 'genres': 'Wrong', 'confidence': .99},
        {'streamId': 7, 'type': 'movie', 'genres': 'Drama', 'confidence': .9},
        {
          'streamId': 7,
          'type': 'movie',
          'genres': 'Duplicate',
          'confidence': .95,
        },
        {'streamId': 7, 'type': 'series', 'genres': 'Guess', 'confidence': .3},
        {
          'streamId': 77,
          'type': 'movie',
          'genres': 'Unknown',
          'confidence': .9,
        },
      ]);
      final repo = ContentEnrichmentRepository(db);
      final count = await CatalogEnrichmentRunner(
        repo,
        api,
        'tr',
        shouldPause: () => false,
      ).runOnce(maxBatchesPerRun: 1);
      expect(count, 1);
      final rows = await repo.lookupMany([(streamId: 7, type: 'movie')]);
      expect(rows.keys, ['7|movie']);
      expect(rows.values.single.genres, 'Drama');
      final skipped = await repo.lookup(7, 'series');
      expect(skipped!.confidence, 0);
      expect(skipped.genres, isNull);
      expect(await db.select(db.contentEnrichment).get(), hasLength(2));
    },
  );
  test(
    'metadata invalidation keeps unrelated types and refreshes derived data',
    () async {
      final repo = ContentEmbeddingsRepository(db);
      final data = ContentEmbeddingsRepository.encode(
        Float32List.fromList([1, 0]),
      );
      await repo.storeBatch([
        for (final type in ['movie', 'series'])
          ContentEmbeddingsCompanion.insert(
            streamId: 7,
            type: type,
            vector: data,
            dims: 2,
          ),
      ]);
      await (db.update(
        db.channels,
      )..where((c) => c.type.equals('movie'))).write(
        const ChannelsCompanion(
          plot: Value('Changed plot'),
          searchText: Value('old'),
        ),
      );
      expect(await repo.lookup(7, 'movie'), isNull);
      expect(await repo.lookup(7, 'series'), isNotNull);
      final channel = await (db.select(
        db.channels,
      )..where((c) => c.type.equals('movie'))).getSingle();
      expect(channel.searchText, isNull);
      await ContentEnrichmentRepository(db).storeBatch([
        ContentEnrichmentCompanion(
          streamId: const Value(7),
          type: const Value('series'),
          genres: const Value('Drama'),
          confidence: const Value(.9),
        ),
      ]);
      expect(await repo.lookup(7, 'series'), isNull);
    },
  );

  test('vector encoding respects slices and rejects nonfinite/zero inputs', () {
    final original = Float32List.fromList([99, 3, 4, 88]);
    final view = Float32List.sublistView(original, 1, 3);
    expect(
      ContentEmbeddingsRepository.decode(
        ContentEmbeddingsRepository.encode(view),
      ),
      [3, 4],
    );
    expect(ContentEmbeddingsRepository.normalize([double.nan]), isEmpty);
    expect(ContentEmbeddingsRepository.normalize([0, 0]), isEmpty);
    expect(ContentEmbeddingsRepository.normalize([3, 4])[0], closeTo(.6, 1e-6));
    expect(ContentEmbeddingsRepository.decode(Uint8List(3)), isEmpty);
  });
  test(
    'semantic ranking requires matching dimensions and stable typed identity',
    () async {
      final repo = ContentEmbeddingsRepository(db);
      for (var id = 1; id <= 520; id++) {
        await repo.storeBatch([
          for (final type in ['movie', 'series'])
            ContentEmbeddingsCompanion.insert(
              streamId: id,
              type: type,
              dims: 2,
              vector: ContentEmbeddingsRepository.encode(
                Float32List.fromList([1, 0]),
              ),
            ),
        ]);
      }
      final pages = await repo.pages(pageSize: 100).toList();
      expect(pages.expand((p) => p).length, 1040);
      expect(pages.every((p) => p.length <= 100), true);
      final hits = await SemanticSearchService(
        repo,
        null,
      ).similarTo(1, 'movie', k: 3);
      expect(hits.map((h) => h.streamId), [2, 3, 4]);
      final invalid = SemanticSearchService.rankPage(
        Float32List.fromList([1, 0]),
        [
          (streamId: 1, type: 'movie', vector: Float32List.fromList([1])),
          (
            streamId: 2,
            type: 'movie',
            vector: Float32List.fromList([double.nan, 0]),
          ),
          (streamId: 3, type: 'movie', vector: Float32List.fromList([1, 0])),
        ],
        3,
        null,
        null,
      );
      expect(invalid.single.streamId, 3);
    },
  );
}
