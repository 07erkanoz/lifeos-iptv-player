import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final withProgress in [false, true]) {
    test(
      'VOD sync persists provider container and direct URL (progress=$withProgress)',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final service = SyncService(db, _Api());
        final account = Account(
          id: 1,
          name: 'test',
          type: 'xtream',
          url: 'https://provider.invalid/',
          username: 'user',
          password: 'p#q',
          isActive: true,
          createdAt: DateTime(2026),
        );
        if (withProgress) {
          await service.syncAllWithProgress(account, (_) {});
        } else {
          await service.syncAll(account);
        }
        final rows = await db.select(db.channels).get();
        final urls = {for (final row in rows) row.streamId: row.streamUrl};
        expect(urls[42], isNull);
        expect(
          rows.firstWhere((r) => r.streamId == 42).containerExtension,
          'mp4',
        );
        expect(urls[43], 'https://cdn.invalid/signed?token=a%2Fb');
        expect(urls[44], isNull);
      },
    );
  }
}

class _Api implements XtreamApiService {
  @override
  Future<List<dynamic>> getCategories(
    String url,
    String username,
    String password,
    String action,
  ) async => [
    {'category_id': '1', 'category_name': 'test'},
  ];

  @override
  Future<List<dynamic>> getStreams(
    String url,
    String username,
    String password,
    String action, {
    String? categoryId,
  }) async => action == 'get_vod_streams'
      ? [
          {
            'stream_id': 42,
            'name': 'Film',
            'category_id': '1',
            'container_extension': 'mp4',
          },
          {
            'stream_id': 43,
            'name': 'Direct',
            'category_id': '1',
            'container_extension': 'mkv',
            'direct_source': 'https://cdn.invalid/signed?token=a%2Fb',
          },
          {'stream_id': 44, 'name': 'Legacy', 'category_id': '1'},
        ]
      : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
