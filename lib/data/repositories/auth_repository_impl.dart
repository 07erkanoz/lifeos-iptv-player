import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/domain/models/account_info.dart';
import 'package:lifeostv/domain/repositories/auth_repository.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_repository_impl.g.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AppDatabase _db;
  final XtreamApiService _apiService;

  AuthRepositoryImpl(this._db, this._apiService);

  @override
  Future<void> loginXtream(String url, String username, String password, {String name = 'Xtream Account'}) async {
    // Normalize URL before authenticating and saving
    final normalizedUrl = XtreamApiService.normalizeUrl(url);

    final authData = await _apiService.authenticate(normalizedUrl, username, password);

    final accountId = await _db.into(_db.accounts).insert(
      AccountsCompanion.insert(
        name: name,
        type: 'xtream',
        url: normalizedUrl,
        username: Value(username),
        password: Value(password),
        isActive: Value(true),
      ),
    );

    // Save server/user info
    await _saveAccountInfo(accountId, authData);
  }

  @override
  Future<void> loadM3U(String source, {bool isFile = false, String name = 'M3U Playlist'}) async {
    // Parse M3U URL to extract Xtream credentials if it's an Xtream M3U link
    final xtreamInfo = _parseXtreamFromM3U(source);

    if (xtreamInfo != null) {
      // It's an Xtream M3U link - save as Xtream account for full API support
      final normalizedUrl = XtreamApiService.normalizeUrl(xtreamInfo['url']!);

      // Try to authenticate first (but save even if it fails)
      try {
        await _apiService.authenticate(normalizedUrl, xtreamInfo['username']!, xtreamInfo['password']!);
      } catch (_) {
        // Server might be temporarily down, still save the account
      }

      await _db.into(_db.accounts).insert(
        AccountsCompanion.insert(
          name: name,
          type: 'xtream',
          url: normalizedUrl,
          username: Value(xtreamInfo['username']),
          password: Value(xtreamInfo['password']),
          isActive: Value(true),
        ),
      );
    } else {
      // Plain M3U URL - save as m3u type
      await _db.into(_db.accounts).insert(
        AccountsCompanion.insert(
          name: name,
          type: 'm3u',
          url: source.trim(),
          isActive: Value(true),
        ),
      );
    }
  }

  /// Parse Xtream credentials from M3U URL
  /// Handles: http://host:port/get.php?username=X&password=Y&type=m3u_plus&output=mpegts
  Map<String, String>? _parseXtreamFromM3U(String source) {
    try {
      final uri = Uri.parse(source.trim());
      final username = uri.queryParameters['username'];
      final password = uri.queryParameters['password'];

      if (username != null && username.isNotEmpty && password != null && password.isNotEmpty) {
        // Rebuild base URL (scheme://host:port)
        final port = uri.hasPort ? ':${uri.port}' : '';
        final baseUrl = '${uri.scheme}://${uri.host}$port';
        return {'url': baseUrl, 'username': username, 'password': password};
      }
    } catch (_) {}
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
      url: url != null ? Value(XtreamApiService.normalizeUrl(url)) : const Value.absent(),
      username: username != null ? Value(username) : const Value.absent(),
      password: password != null ? Value(password) : const Value.absent(),
    );
    await (_db.update(_db.accounts)..where((tbl) => tbl.id.equals(accountId)))
        .write(companion);
  }

  /// Validate account connection (re-authenticate)
  Future<AccountInfo?> validateAccount(Account account) async {
    if (account.type != 'xtream') return null;
    try {
      final url = XtreamApiService.normalizeUrl(account.url);
      final data = await _apiService.authenticate(url, account.username!, account.password!);
      final info = AccountInfo.fromXtreamResponse(data);
      await _saveAccountInfo(account.id, data);
      return info;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteAccount(int accountId) async {
    await (_db.delete(_db.accounts)..where((tbl) => tbl.id.equals(accountId))).go();
    // Clean up account info
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('acct_info_${accountId}_'));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  @override
  Future<List<Account>> getAccounts() async {
    return await _db.select(_db.accounts).get();
  }

  @override
  Future<Account?> getCurrentAccount() async {
    return await (_db.select(_db.accounts)..where((tbl) => tbl.isActive.equals(true))).getSingleOrNull();
  }

  /// Clear all user data when switching to a new account:
  /// cache, favorites, watch history, series tracking, categories, channels, EPG
  Future<void> clearUserDataForNewAccount() async {
    // Clear API cache
    ApiCache.instance.clear();

    // Clear content tables (channels, categories, programs belong to previous account)
    await _db.delete(_db.channels).go();
    await _db.delete(_db.categories).go();
    await _db.delete(_db.programs).go();

    // Clear user data
    await _db.delete(_db.favorites).go();
    await _db.delete(_db.playbackProgress).go();
    await _db.delete(_db.seriesTracking).go();
  }

  // ─── Account Info Persistence ───────────────────────────────────────────

  Future<void> _saveAccountInfo(int accountId, Map<String, dynamic> authData) async {
    try {
      final info = AccountInfo.fromXtreamResponse(authData);
      final prefs = await SharedPreferences.getInstance();
      final map = info.toMap();
      for (final e in map.entries) {
        await prefs.setString('acct_info_${accountId}_${e.key}', e.value);
      }
    } catch (_) {}
  }

  /// Get cached account info (from last authentication)
  static Future<AccountInfo?> getAccountInfo(int accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final key in ['status', 'expiry', 'max_conn', 'active_conn', 'created', 'is_trial']) {
        final val = prefs.getString('acct_info_${accountId}_$key');
        if (val != null) map[key] = val;
      }
      if (map.isEmpty) return null;
      return AccountInfo.fromMap(map);
    } catch (_) {
      return null;
    }
  }
}

@riverpod
AuthRepository authRepository(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  final api = ref.watch(xtreamApiServiceProvider);
  return AuthRepositoryImpl(db, api);
}
