import 'dart:typed_data';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';

void main() {
  late AppDatabase root, db;
  late ContentEmbeddingsRepository repo;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = AppDatabase.forTesting(NativeDatabase.memory());
    db = root.forAccount(1);
    repo = ContentEmbeddingsRepository(db);
    for (final account in [1, 2]) {
      final d = root.forAccount(account);
      for (final type in ['movie', 'series']) {
        await d
            .into(d.channels)
            .insert(
              ChannelsCompanion.insert(
                streamId: 7,
                name: 'Original',
                type: type,
                categoryId: 'cat',
                genre: const Value('Drama'),
              ),
            );
      }
    }
  });
  tearDown(() async {
    await root.close();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });
  ContentEmbeddingsCompanion vector(String type) =>
      ContentEmbeddingsCompanion.insert(
        streamId: 7,
        type: type,
        vector: ContentEmbeddingsRepository.encode(
          Float32List.fromList([1, 0]),
        ),
        dims: 2,
      );
  test(
    'changed or deleted source rejects stale responses while current typed row commits',
    () async {
      final pending = await repo.pendingItems();
      await (db.update(db.channels)..where((c) => c.type.equals('movie')))
          .write(const ChannelsCompanion(name: Value('Changed')));
      final count = await repo.storeCurrentBatch([
        for (final source in pending)
          (source: source, vector: vector(source.type)),
      ]);
      expect(count, 1);
      expect(await repo.lookup(7, 'movie'), isNull);
      expect(await repo.lookup(7, 'series'), isNotNull);
      expect(
        await ContentEmbeddingsRepository(
          root.forAccount(2),
        ).lookup(7, 'series'),
        isNull,
      );
      await (db.delete(
        db.channels,
      )..where((c) => c.type.equals('series'))).go();
      expect(
        await repo.storeCurrentBatch([
          (
            source: pending.firstWhere((p) => p.type == 'series'),
            vector: vector('series'),
          ),
        ]),
        0,
      );
    },
  );
  test(
    'enrichment change after HTTP invalidates model input inside transaction',
    () async {
      final pending = (await repo.pendingItems()).firstWhere(
        (p) => p.type == 'movie',
      );
      await db
          .into(db.contentEnrichment)
          .insert(
            ContentEnrichmentCompanion.insert(
              streamId: 7,
              type: 'movie',
              confidence: const Value(.9),
              themes: const Value('New theme'),
            ),
          );
      expect(
        await repo.storeCurrentBatch([
          (source: pending, vector: vector('movie')),
        ]),
        0,
      );
      final current = (await repo.pendingItems()).firstWhere(
        (p) => p.type == 'movie',
      );
      expect(
        await repo.storeCurrentBatch([
          (source: current, vector: vector('movie')),
        ]),
        1,
      );
      await (db.update(db.channels)..where((c) => c.type.equals('movie')))
          .write(const ChannelsCompanion(plot: Value('A later plot')));
      expect(await repo.lookup(7, 'movie'), isNull);
    },
  );
  test('cancelled commit leaves no vectors', () async {
    final pending = (await repo.pendingItems()).first;
    expect(
      await repo.storeCurrentBatch([
        (source: pending, vector: vector(pending.type)),
      ], shouldCancel: () => true),
      0,
    );
    expect(await repo.embeddedCount(), 0);
  });
}
