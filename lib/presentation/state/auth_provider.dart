import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/main.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final savedAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  return repo.getAccounts();
});

final currentAccountProvider = FutureProvider<Account?>((ref) async {
  final settings = ref.watch(settingsProvider);
  final repo = ref.watch(authRepositoryProvider);

  // First try default account from settings
  if (settings.defaultAccountId != null) {
    final accounts = await repo.getAccounts();
    final match = accounts.where((a) => a.id == settings.defaultAccountId);
    if (match.isNotEmpty) return match.first;
  }

  // Fallback to first active account
  return repo.getCurrentAccount();
});

/// Triggers tiered sync when account is available.
/// Tier 1 (30m): categories, Tier 2 (2h): channel delta,
/// Tier 3 (6h): full refresh, Tier 4 (1h): watched series
final initialSyncProvider = FutureProvider<void>((ref) async {
  final account = await ref.watch(currentAccountProvider.future);
  if (account == null) return;

  try {
    final prefs = ref.read(sharedPreferencesProvider);
    final meta = SyncMetadata(prefs);
    final syncService = ref.read(syncServiceProvider);
    await syncService.runTieredSync(account, meta);
  } catch (_) {
    // On error, attempt full sync as fallback
    try {
      final syncService = ref.read(syncServiceProvider);
      await syncService.syncAll(account);
    } catch (_) {}
  }
});

/// Force sync regardless of time interval (for manual refresh)
final forceSyncProvider = FutureProvider.family<void, int>((ref, accountId) async {
  final account = await ref.watch(currentAccountProvider.future);
  if (account == null) return;

  final syncService = ref.read(syncServiceProvider);

  // Clear account-specific cache before full refresh
  if (account.type == 'xtream' && account.username != null) {
    final url = account.url.replaceAll(RegExp(r'/+$'), '');
    ApiCache.instance.invalidateForAccount('${account.username}@$url');
  }

  await syncService.syncAll(account);

  // Reset all tier timestamps so tiered sync recognizes the fresh state
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    final meta = SyncMetadata(prefs);
    await meta.resetAllTiers();
    // Mark all tiers as synced since we just did a full sync
    await meta.markTierSynced(1);
    await meta.markTierSynced(2);
    await meta.markTierSynced(3);
    await meta.markTierSynced(4);
  } catch (_) {}
});
