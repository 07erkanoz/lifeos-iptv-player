import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuthRepositoryImpl repo;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'default_account_id': 1});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AuthRepositoryImpl(db, _Api());
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: const Value(1),
            name: 'Old default',
            type: 'xtream',
            url: 'https://old.invalid',
            isActive: const Value(true),
          ),
        );
    container = ProviderContainer(
      overrides: [
        rootDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  for (final type in ['xtream', 'm3u']) {
    test('new $type account wins over previous default preference', () async {
      expect((await container.read(currentAccountProvider.future))?.id, 1);
      if (type == 'xtream') {
        await repo.loginXtream('https://new.invalid', 'new-user', 'synthetic');
      } else {
        await repo.loadM3U('https://new.invalid/playlist.m3u');
      }
      container.invalidate(currentAccountProvider);
      final selected = await container.read(currentAccountProvider.future);
      expect(selected?.id, 2);
      expect(selected?.url, startsWith('https://new.invalid'));
      expect((await repo.getAccounts()).where((a) => a.isActive).single.id, 2);
    });
  }

  test('invalid activation preserves the current active account', () async {
    await expectLater(repo.setActiveAccount(999), throwsStateError);
    expect((await repo.getCurrentAccount())?.id, 1);
  });

  test('valid activation picks exactly one account', () async {
    await repo.loadM3U('https://new.invalid/playlist.m3u');
    await repo.setActiveAccount(1);
    expect((await repo.getAccounts()).where((a) => a.isActive).single.id, 1);
    expect((await container.read(currentAccountProvider.future))?.id, 1);
  });
}

class _Api extends XtreamApiService {
  _Api() : super(Dio());
  @override
  Future<Map<String, dynamic>> authenticate(
    String url,
    String username,
    String password,
  ) async => {
    'user_info': {'auth': 1, 'status': 'Active'},
  };
}
