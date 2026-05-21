import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;

part 'ai_rail_cache_repository.g.dart';

/// Lightweight key-value cache for AI-generated dashboard rails
/// (hero billboard, weekly digest, greeting…).
///
/// Backed by SharedPreferences rather than Drift because the
/// per-entry payload is small (under 1 KB of streamId + reason +
/// headline) and we want zero schema-migration risk. Each cache
/// entry is one JSON-encoded blob storing `payload`, `sourceHash`
/// and `generatedAt`.
///
/// Eviction is lazy: callers pass a [ttl]; the lookup returns null
/// if the row is older than that OR if the sourceHash they supply
/// doesn't match the stored one (the user's taste state changed).
class AiRailCacheRepository {
  final SharedPreferences _prefs;

  AiRailCacheRepository(this._prefs);

  static const _prefix = 'ai_rail_cache:';

  /// Read a cached blob.
  ///
  /// Returns `null` when:
  ///   * no row exists for [cacheKey],
  ///   * the stored `sourceHash` differs from [sourceHash] (state
  ///     drift — the taste signals that produced this row are no
  ///     longer accurate),
  ///   * the row is older than [ttl].
  ///
  /// Otherwise returns the decoded payload Map.
  Map<String, dynamic>? lookup({
    required String cacheKey,
    required String sourceHash,
    required Duration ttl,
  }) {
    final raw = _prefs.getString('$_prefix$cacheKey');
    if (raw == null) return null;
    Map<String, dynamic>? row;
    try {
      row = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if (row['sourceHash'] != sourceHash) return null;
    final ts = row['generatedAt'];
    if (ts is! int) return null;
    final age =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (age > ttl) return null;
    final payload = row['payload'];
    if (payload is! Map<String, dynamic>) return null;
    return payload;
  }

  /// Upsert the cache row for [cacheKey].
  Future<void> store({
    required String cacheKey,
    required String sourceHash,
    required Map<String, dynamic> payload,
  }) async {
    final row = jsonEncode({
      'sourceHash': sourceHash,
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
      'payload': payload,
    });
    await _prefs.setString('$_prefix$cacheKey', row);
  }

  /// Drop the cache row for [cacheKey]. Used by per-rail refresh
  /// affordances.
  Future<void> clear(String cacheKey) async {
    await _prefs.remove('$_prefix$cacheKey');
  }

  /// FNV-1a 32-bit hash. Same algorithm the personalised-picks
  /// repository uses so consumers stay consistent across rails.
  static String fingerprint(String blob) {
    var h = 0x811c9dc5;
    for (final code in blob.codeUnits) {
      h = (h ^ code) & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

@Riverpod(keepAlive: true)
AiRailCacheRepository aiRailCacheRepository(Ref ref) {
  return AiRailCacheRepository(ref.watch(sharedPreferencesProvider));
}
