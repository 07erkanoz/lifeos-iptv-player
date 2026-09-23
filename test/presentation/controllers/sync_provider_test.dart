import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_budget.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _Sync sync;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final id in [1, 2]) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              name: 'Account $id',
              type: 'xtream',
              url: 'https://synthetic.invalid',
              isActive: Value(id == 1),
            ),
          );
    }
    final active = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(1))).getSingle();
    sync = _Sync(db);
    container = ProviderContainer(
      overrides: [
        rootDatabaseProvider.overrideWithValue(db),
        currentAccountProvider.overrideWith((_) async => active),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        syncServiceProvider.overrideWithValue(sync),
        contentRepositoryProvider.overrideWithValue(
          ContentRepository(db, sync, () => 1),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'manual refresh uses requested ID rather than current account',
    () async {
      await container.read(forceSyncProvider(2).future);
      expect(sync.fullAccounts, [2]);
    },
  );

  test(
    'initial failure does not launch a hidden full fallback or provider retry',
    () async {
      final listener = container.listen(initialSyncProvider, (_, _) {});
      addTearDown(listener.close);
      await expectLater(
        container.read(initialSyncProvider.future),
        throwsA(isA<SyncFailure>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(sync.tieredCalls, 1);
      expect(sync.fullAccounts, isEmpty);
    },
  );
}

class _Sync extends SyncService {
  _Sync(AppDatabase db) : super(db, XtreamApiService(Dio()));
  final fullAccounts = <int>[];
  int tieredCalls = 0;
  @override
  Future<void> syncAll(Account account) async {
    fullAccounts.add(account.id);
  }

  @override
  Future<void> runTieredSync(Account account, SyncMetadata meta) async {
    tieredCalls++;
    throw const SyncFailure('Synthetic failure');
  }
}
