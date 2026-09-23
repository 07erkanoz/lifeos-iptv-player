import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final savedAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getAccounts();
});

final currentAccountProvider = FutureProvider<Account?>((ref) async {
  ref.watch(databaseAccountIdProvider);
  ref.watch(databaseEpochProvider);
  final repo = ref.watch(authRepositoryProvider);
  // DB activation and the downloaded catalogue share one authority. A stale
  // default_account_id preference must never override a newly added account.
  return repo.getCurrentAccount();
});

/// Triggers tiered sync when account is available.
/// Tier 1 (30m): categories, Tier 2 (2h): channel delta,
/// Tier 3 (24h): full refresh, Tier 4 (1h): watched series
final initialSyncProvider = FutureProvider<void>((ref) async {
  // Account changes start the new account’s sync; per-account metadata
  // keeps repeated triggers from duplicating a tiered run.
  final account = await ref.watch(currentAccountProvider.future);
  if (account == null) return;

  final prefs = ref.read(sharedPreferencesProvider);
  final meta = SyncMetadata(prefs, accountId: account.id);
  final sync = ref.read(syncServiceProvider);
  final content = ref.read(contentRepositoryProvider).forAccount(account.id);
  await sync.runTieredSync(account, meta);
  await content.reapplyCategoryPrefs();
}, retry: (_, _) => null);

/// Manual refresh uses the requested ID, even if the user switches accounts.
final forceSyncProvider = FutureProvider.family<void, int>((
  ref,
  accountId,
) async {
  final db = ref.read(rootDatabaseProvider);
  final account = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(accountId))).getSingleOrNull();
  if (account == null) throw StateError('Account does not exist');
  final sync = ref.read(syncServiceProvider);
  await sync.syncAll(account);
}, retry: (_, _) => null);
