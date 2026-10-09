// flutter test tool/embedding_benchmark_test.dart --reporter expanded
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';
import 'package:lifeostv/data/services/semantic_search_service.dart';
import '../../tool/playlist_benchmark_test.dart' show measure;

void main() {
  test('10k x 768 semantic vectors with bounded worker ranking', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ContentEmbeddingsRepository(db);
    final vector = ContentEmbeddingsRepository.normalize(
      List.generate(768, (i) => (i % 17 + 1).toDouble()),
    );
    for (var start = 0; start < 10000; start += 500) {
      await repo.storeBatch([
        for (var i = start; i < start + 500; i++)
          ContentEmbeddingsCompanion.insert(
            streamId: i,
            type: 'movie',
            vector: ContentEmbeddingsRepository.encode(vector),
            dims: 768,
          ),
      ]);
    }
    final samples = <Map<String, dynamic>>[];
    samples.add(
      await measure('semantic-ranking', 60, 0, 'full-main', () async {
        final rows = await db.select(db.contentEmbeddings).get();
        final all = [
          for (final r in rows)
            (
              streamId: r.streamId,
              type: r.type,
              vector: ContentEmbeddingsRepository.decode(r.vector),
            ),
        ];
        return SemanticSearchService.rankPage(
          Float32List.fromList(vector),
          all,
          60,
          0,
          'movie',
        ).length;
      }),
    );
    samples.add(
      await measure('semantic-ranking', 60, 0, 'paged-worker', () async {
        final hits = await SemanticSearchService(
          repo,
          null,
        ).similarTo(0, 'movie', k: 60);
        expect(hits.first.streamId, 1);
        return hits.length;
      }),
    );
    final output = {
      'note':
          'Synthetic Linux host test, 10000 vectors, 768 dimensions. Timer gaps are not video frames. RSS includes test process and SQLite fixtures; this is not an isolated peak-RAM measurement.',
      'samples': samples,
    };
    File(
      'docs/release-audit-2026-10-09/embedding-benchmark.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(output));
    // ignore: avoid_print
    print(jsonEncode(output));
  });
}
