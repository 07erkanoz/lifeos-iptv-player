/// SWR result: returns data along with staleness flag
class StaleCacheResult<T> {
  final T data;
  final bool isStale;
  const StaleCacheResult({required this.data, required this.isStale});
}

/// In-memory cache with TTL + SWR (Stale-While-Revalidate) support.
/// Prevents redundant API calls and reduces server load.
class ApiCache {
  static final ApiCache instance = ApiCache._();
  ApiCache._();

  final Map<String, _CacheEntry> _cache = {};

  /// Default TTL values for different content types
  static const vodInfoTtl = Duration(minutes: 30);
  static const seriesInfoTtl = Duration(minutes: 30);
  static const epgTtl = Duration(hours: 2);
  static const epgAllTtl = Duration(hours: 2);
  static const categoriesTtl = Duration(minutes: 30);
  static const streamsTtl = Duration(hours: 6);

  /// Get cached value, returns null if expired or not found
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  /// SWR: Get cached value even if stale. Returns null only if key not found.
  /// If expired, returns data with isStale=true (caller can revalidate in background).
  StaleCacheResult<T>? getStale<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    final isStale = DateTime.now().isAfter(entry.expiresAt);
    return StaleCacheResult<T>(
      data: entry.value as T,
      isStale: isStale,
    );
  }

  /// SWR fetch: returns cached data immediately (even if stale),
  /// and revalidates in background if stale. Blocks only on cache miss.
  Future<T> fetchWithCache<T>(
    String key,
    Future<T> Function() fetchFn,
    Duration ttl, {
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      final data = await fetchFn();
      set(key, data, ttl);
      return data;
    }

    final staleResult = getStale<T>(key);
    if (staleResult != null) {
      if (!staleResult.isStale) {
        // Fresh cache — instant return
        return staleResult.data;
      }
      // Stale cache — return old data, revalidate in background
      _revalidateInBackground(key, fetchFn, ttl);
      return staleResult.data;
    }

    // Cache miss — blocking fetch
    final data = await fetchFn();
    set(key, data, ttl);
    return data;
  }

  /// Fire-and-forget background revalidation
  void _revalidateInBackground<T>(
    String key,
    Future<T> Function() fetchFn,
    Duration ttl,
  ) {
    fetchFn().then((data) {
      set(key, data, ttl);
    }).catchError((_) {
      // Background update failed — stale cache continues to serve
    });
  }

  /// Store value with TTL
  void set<T>(String key, T value, Duration ttl) {
    _cache[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// Remove specific cache entry
  void invalidate(String key) {
    _cache.remove(key);
  }

  /// Remove all entries matching a prefix
  void invalidatePrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Remove all entries containing the identifier (account-specific invalidation)
  void invalidateForAccount(String accountIdentifier) {
    _cache.removeWhere((key, _) => key.contains(accountIdentifier));
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
  }

  /// Remove expired entries (called periodically)
  void cleanup() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => now.isAfter(entry.expiresAt));
  }

  /// Check if a valid (non-expired) entry exists
  bool has(String key) {
    return get<dynamic>(key) != null;
  }

  /// Number of entries currently cached
  int get length => _cache.length;
}

class _CacheEntry {
  final dynamic value;
  final DateTime expiresAt;

  _CacheEntry({required this.value, required this.expiresAt});
}
