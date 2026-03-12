import 'package:shared_preferences/shared_preferences.dart';

/// Tiered refresh intervals matching Tauri implementation
class TierTtl {
  /// Tier 1: Category list refresh (30 minutes)
  static const tier1 = Duration(minutes: 30);

  /// Tier 2: Channel count delta check (2 hours)
  static const tier2 = Duration(hours: 2);

  /// Tier 3: Full content refresh (6 hours)
  static const tier3 = Duration(hours: 6);

  /// Tier 4: Watched series episode check (1 hour)
  static const tier4 = Duration(hours: 1);
}

/// Tracks sync state across tiers, daily API call count, and mutex
class SyncMetadata {
  static const _keyPrefix = 'sync_meta_';
  static const _keyTier1 = '${_keyPrefix}tier1_last';
  static const _keyTier2 = '${_keyPrefix}tier2_last';
  static const _keyTier3 = '${_keyPrefix}tier3_last';
  static const _keyTier4 = '${_keyPrefix}tier4_last';
  static const _keyDailyCount = '${_keyPrefix}daily_count';
  static const _keyDailyDate = '${_keyPrefix}daily_date';

  final SharedPreferences _prefs;

  /// Max daily API calls
  static const maxDailyRequests = 2000;

  /// In-memory mutex to prevent concurrent sync runs
  bool _syncing = false;
  bool get isSyncing => _syncing;

  SyncMetadata(this._prefs);

  /// Check if a specific tier is due for refresh
  bool isTierDue(int tier) {
    final key = _tierKey(tier);
    final ttl = _tierTtl(tier);
    if (key == null || ttl == null) return false;

    final lastSync = _prefs.getInt(key) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSync;
    return elapsed > ttl.inMilliseconds;
  }

  /// Mark a tier as just synced
  Future<void> markTierSynced(int tier) async {
    final key = _tierKey(tier);
    if (key != null) {
      await _prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Get daily API call count (auto-resets on new day)
  int get dailyApiCalls {
    _resetDailyIfNeeded();
    return _prefs.getInt(_keyDailyCount) ?? 0;
  }

  /// Check if daily limit is exceeded
  bool get isDailyLimitExceeded => dailyApiCalls >= maxDailyRequests;

  /// Increment daily API call counter
  Future<void> incrementApiCalls([int count = 1]) async {
    _resetDailyIfNeeded();
    final current = _prefs.getInt(_keyDailyCount) ?? 0;
    await _prefs.setInt(_keyDailyCount, current + count);
  }

  /// Try to acquire sync mutex. Returns true if acquired.
  bool tryAcquireMutex() {
    if (_syncing) return false;
    _syncing = true;
    return true;
  }

  /// Release sync mutex
  void releaseMutex() {
    _syncing = false;
  }

  /// Reset all tier timestamps (force re-sync on next check)
  Future<void> resetAllTiers() async {
    await _prefs.remove(_keyTier1);
    await _prefs.remove(_keyTier2);
    await _prefs.remove(_keyTier3);
    await _prefs.remove(_keyTier4);
  }

  void _resetDailyIfNeeded() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = _prefs.getString(_keyDailyDate) ?? '';
    if (savedDate != today) {
      _prefs.setInt(_keyDailyCount, 0);
      _prefs.setString(_keyDailyDate, today);
    }
  }

  String? _tierKey(int tier) {
    switch (tier) {
      case 1: return _keyTier1;
      case 2: return _keyTier2;
      case 3: return _keyTier3;
      case 4: return _keyTier4;
      default: return null;
    }
  }

  Duration? _tierTtl(int tier) {
    switch (tier) {
      case 1: return TierTtl.tier1;
      case 2: return TierTtl.tier2;
      case 3: return TierTtl.tier3;
      case 4: return TierTtl.tier4;
      default: return null;
    }
  }
}
