import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/domain/models/account_info.dart';
import 'package:lifeostv/domain/repositories/auth_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_repository_impl.g.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AppDatabase _db;
  final XtreamApiService _apiService;

  AuthRepositoryImpl(this._db, this._apiService);

  /// Deactivate every account row. Run inside a transaction together
  /// with whatever activation is happening next so the DB never spends
  /// any time with zero (or more than one) `isActive == true` rows.
  Future<void> _deactivateAllAccounts() async {
    await _db
        .update(_db.accounts)
        .write(const AccountsCompanion(isActive: Value(false)));
  }

  @override
  Future<void> loginXtream(
    String url,
    String username,
    String password, {
    String name = 'Xtream Account',
  }) async {
    // Normalize URL before authenticating and saving
    final normalizedUrl = XtreamApiService.normalizeUrl(url);

    final authData = await _apiService.authenticate(
      normalizedUrl,
      username,
      password,
    );

    // Insert the new account as the *single* active account.
    // Previously this just set `isActive: true` without touching the
    // existing rows, which left multiple actives in the DB and made
    // `getCurrentAccount()`'s `getSingleOrNull()` throw / pick the
    // wrong row depending on insertion order.
    final accountId = await _db.transaction(() async {
      await _deactivateAllAccounts();
      return _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: name,
              type: 'xtream',
              url: normalizedUrl,
              username: Value(username),
              password: Value(password),
              isActive: Value(true),
            ),
          );
    });

    // Save server/user info
    await _saveAccountInfo(accountId, authData);
  }

  @override
  Future<void> loadM3U(
    String source, {
    bool isFile = false,
    String name = 'M3U Playlist',
  }) async {
    final xtreamInfo = isFile ? null : _parseXtreamFromM3U(source);
    Map<String, dynamic>? authData;
    if (xtreamInfo != null) {
      try {
        authData = await _apiService.authenticate(
          xtreamInfo['url']!,
          xtreamInfo['username']!,
          xtreamInfo['password']!,
        );
      } catch (_) {
        // A get.php playlist does not guarantee that the Xtream API exists.
        // Preserve the exact source URL when capability verification fails.
      }
    }
    final verified = xtreamInfo != null && authData != null;
    final id = await _db.transaction(() async {
      await _deactivateAllAccounts();
      return _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: name,
              type: verified ? 'xtream' : 'm3u',
              url: verified ? xtreamInfo['url']! : source.trim(),
              username: verified
                  ? Value(xtreamInfo['username'])
                  : const Value.absent(),
              password: verified
                  ? Value(xtreamInfo['password'])
                  : const Value.absent(),
              isActive: const Value(true),
            ),
          );
    });
    if (verified) await _saveAccountInfo(id, authData);
  }

  /// Parse Xtream credentials from M3U URL
  /// Handles: http://host:port/get.php?username=X&password=Y&type=m3u_plus&output=mpegts
  ///
  /// Returns `null` on any parse failure (caller will fall back to
  /// treating the source as a plain M3U URL). Logs the failure in
  /// debug so a user reporting "my Xtream M3U link is being treated as
  /// plain M3U" has a breadcrumb in the logs instead of silent
  /// downgrade.
  Map<String, String>? _parseXtreamFromM3U(String source) {
    try {
      final uri = Uri.parse(source.trim());
      if (uri.pathSegments.isEmpty ||
          uri.pathSegments.last.toLowerCase() != 'get.php')
        return null;
      final username = uri.queryParameters['username'];
      final password = uri.queryParameters['password'];

      if (username != null &&
          username.isNotEmpty &&
          password != null &&
          password.isNotEmpty) {
        // Rebuild base URL (scheme://host:port)
        final baseUrl = XtreamApiService.normalizeUrl(source);
        return {'url': baseUrl, 'username': username, 'password': password};
      }
    } catch (e) {
      debugPrint('[Auth] Playlist address could not be parsed.');
    }
    return null;
  }

  @override
  Future<void> logout() async {
    // Logic to deactivate account
  }

  @override
  Future<void> updateAccountName(int accountId, String name) async {
    await (_db.update(_db.accounts)..where((tbl) => tbl.id.equals(accountId)))
        .write(AccountsCompanion(name: Value(name)));
  }

  /// Update full account credentials (URL, username, password)
  Future<void> updateAccountCredentials(
    int accountId, {
    String? name,
    String? url,
    String? username,
    String? password,
  }) async {
    final companion = AccountsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      url: url != null
          ? Value(XtreamApiService.normalizeUrl(url))
          : const Value.absent(),
      username: username != null ? Value(username) : const Value.absent(),
      password: password != null ? Value(password) : const Value.absent(),
    );
    await (_db.update(
      _db.accounts,
    )..where((tbl) => tbl.id.equals(accountId))).write(companion);
  }

  /// Validate account connection (re-authenticate)
  Future<AccountInfo?> validateAccount(Account account) async {
    if (account.type != 'xtream') return null;
    try {
      final url = XtreamApiService.normalizeUrl(account.url);
      final data = await _apiService.authenticate(
        url,
        account.username!,
        account.password!,
      );
      final info = AccountInfo.fromXtreamResponse(data);
      await _saveAccountInfo(account.id, data);
      return info;
    } catch (e) {
      debugPrint('[Auth] validateAccount(${account.id}) failed: $e');
      return null;
    }
  }

  @override
  Future<void> deleteAccount(int accountId) async {
    _db.blockAccount(accountId);
    try {
      await _db.transaction(() async {
        for (final table in _db.allTables) {
          final column = table.columnsByName['account_id'];
          if (column == null) continue;
          await (_db.delete(table)..where(
                (_) => (column as GeneratedColumn<int>).equals(accountId),
              ))
              .go();
        }
        await (_db.delete(
          _db.accounts,
        )..where((tbl) => tbl.id.equals(accountId))).go();
        if (await getCurrentAccount() == null) {
          final next =
              await (_db.select(_db.accounts)
                    ..orderBy([(t) => OrderingTerm.desc(t.id)])
                    ..limit(1))
                  .getSingleOrNull();
          if (next != null) await setActiveAccount(next.id);
        }
      });
    } catch (_) {
      _db.unblockAccount(accountId);
      rethrow;
    }
    // Clean up account info
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (k) => k.startsWith('acct_info_${accountId}_'),
      );
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('[Auth] deleteAccount prefs cleanup failed: $e');
    }
  }

  @override
  Future<List<Account>> getAccounts() async {
    return await _db.select(_db.accounts).get();
  }

  @override
  Future<Account?> getCurrentAccount() async {
    // Robust against multiple-active rows: if the invariant was ever
    // violated (older builds didn't enforce it on insert), prefer the
    // most-recently-inserted active account and limit to 1 so drift's
    // single-result helper doesn't throw.
    return await (_db.select(_db.accounts)
          ..where((tbl) => tbl.isActive.equals(true))
          ..orderBy([
            (tbl) => OrderingTerm(expression: tbl.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  @override
  Future<void> setActiveAccount(int accountId) async {
    // Single transaction so we don't briefly land in a "zero active" or
    // "two active" state. After this call the `isActive == true` rows
    // are exactly the one with id == accountId (assuming the row exists).
    await _db.transaction(() async {
      final target = await (_db.select(
        _db.accounts,
      )..where((row) => row.id.equals(accountId))).getSingleOrNull();
      if (target == null) throw StateError('Account does not exist');
      await _deactivateAllAccounts();
      await (_db.update(_db.accounts)..where((tbl) => tbl.id.equals(accountId)))
          .write(const AccountsCompanion(isActive: Value(true)));
    });
  }

  // ─── Account Info Persistence ───────────────────────────────────────────

  Future<void> _saveAccountInfo(
    int accountId,
    Map<String, dynamic> authData,
  ) async {
    try {
      final info = AccountInfo.fromXtreamResponse(authData);
      final prefs = await SharedPreferences.getInstance();
      final map = info.toMap();
      for (final e in map.entries) {
        await prefs.setString('acct_info_${accountId}_${e.key}', e.value);
      }
    } catch (e) {
      debugPrint('[Auth] _saveAccountInfo failed: $e');
    }
  }

  /// Get cached account info (from last authentication)
  static Future<AccountInfo?> getAccountInfo(int accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final key in [
        'status',
        'expiry',
        'max_conn',
        'active_conn',
        'created',
        'is_trial',
      ]) {
        final val = prefs.getString('acct_info_${accountId}_$key');
        if (val != null) map[key] = val;
      }
      if (map.isEmpty) return null;
      return AccountInfo.fromMap(map);
    } catch (e) {
      debugPrint('[Auth] getAccountInfo($accountId) failed: $e');
      return null;
    }
  }
}

@riverpod
AuthRepository authRepository(Ref ref) {
  final db = ref.watch(rootDatabaseProvider);
  final api = ref.watch(xtreamApiServiceProvider);
  return AuthRepositoryImpl(db, api);
}
