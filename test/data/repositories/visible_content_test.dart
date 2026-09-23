import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';

void main() {
  test(
    'AI resolution rejects ambiguous, hidden, adult and foreign content',
    () async {
      final root = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(root.close);
      for (final accountId in [1, 2]) {
        final db = root.forAccount(accountId);
        for (final type in ['movie', 'series']) {
          for (final (cat, name, hidden) in [
            ('normal', 'Normal', false),
            ('hidden', 'Hidden', true),
            ('adult', 'XXX Adult', false),
          ]) {
            await db
                .into(db.categories)
                .insert(
                  CategoriesCompanion.insert(
                    id: cat,
                    name: name,
                    type: type,
                    isHidden: Value(hidden),
                  ),
                );
          }
        }
        for (final (id, type, cat) in [
          (7, 'movie', 'normal'),
          (7, 'series', 'normal'),
          (8, 'movie', 'hidden'),
          (9, 'movie', 'adult'),
          (accountId * 10, 'movie', 'normal'),
        ]) {
          await db
              .into(db.channels)
              .insert(
                ChannelsCompanion.insert(
                  streamId: id,
                  name: 'Item $id',
                  type: type,
                  categoryId: cat,
                ),
              );
        }
      }
      final db = root.forAccount(1);
      final repo = ContentRepository(
        db,
        SyncService(db, XtreamApiService(Dio())),
        () => 1,
        autoHideAdult: () => true,
      );
      expect(await repo.getVisibleChannel(7), isNull);
      expect((await repo.getVisibleChannel(7, type: 'series'))?.type, 'series');
      expect(await repo.getVisibleChannel(8, type: 'movie'), isNull);
      expect(await repo.getVisibleChannel(9, type: 'movie'), isNull);
      expect(await repo.getVisibleChannel(20, type: 'movie'), isNull);
      expect((await repo.getVisibleChannel(10, type: 'movie'))?.accountId, 1);
    },
  );
}
