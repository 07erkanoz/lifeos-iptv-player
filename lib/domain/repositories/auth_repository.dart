import 'package:lifeostv/data/datasources/local/database.dart';

abstract class AuthRepository {
  /// Authenticates using Xtream Codes credentials.
  /// Throws exception on failure.
  Future<void> loginXtream(String url, String username, String password, {String name = 'Xtream Account'});

  /// Loads playlist from M3U URL or File path.
  Future<void> loadM3U(String source, {bool isFile = false, String name = 'M3U Playlist'});

  /// Updates account name.
  Future<void> updateAccountName(int accountId, String name);

  /// Deletes an account.
  Future<void> deleteAccount(int accountId);

  /// Logs out the current active account.
  Future<void> logout();

  /// Gets all saved accounts.
  Future<List<Account>> getAccounts();
  Future<Account?> getCurrentAccount();
}
