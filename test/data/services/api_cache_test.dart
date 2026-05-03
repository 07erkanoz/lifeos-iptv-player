import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/data/services/api_cache.dart';

void main() {
  // ApiCache is a singleton — clear it between tests so leftover entries
  // from one test can't taint the next.
  setUp(() {
    ApiCache.instance.clear();
  });

  group('get / set / TTL', () {
    test('set then get returns the same value before TTL elapses', () {
      ApiCache.instance.set('k', 42, const Duration(seconds: 5));
      expect(ApiCache.instance.get<int>('k'), 42);
    });

    test('get returns null when the key was never set', () {
      expect(ApiCache.instance.get<String>('missing'), isNull);
    });

    test('expired entry is evicted on read and returns null', () async {
      ApiCache.instance.set('k', 'v', const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(ApiCache.instance.get<String>('k'), isNull);
      // The eviction also drops it from the internal map.
      expect(ApiCache.instance.length, 0);
    });

    test('has() agrees with get() for non-expired entries', () {
      ApiCache.instance.set('k', 1, const Duration(seconds: 5));
      expect(ApiCache.instance.has('k'), isTrue);
    });
  });

  group('SWR — getStale / fetchWithCache', () {
    test('getStale returns data with isStale=false when fresh', () {
      ApiCache.instance.set('k', 'fresh', const Duration(seconds: 5));
      final r = ApiCache.instance.getStale<String>('k');
      expect(r, isNotNull);
      expect(r!.data, 'fresh');
      expect(r.isStale, isFalse);
    });

    test('getStale returns data with isStale=true after TTL elapses', () async {
      ApiCache.instance.set('k', 'old', const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final r = ApiCache.instance.getStale<String>('k');
      expect(r, isNotNull);
      expect(r!.data, 'old', reason: 'SWR keeps the stale value visible');
      expect(r.isStale, isTrue);
    });

    test('getStale returns null only on a true miss', () {
      expect(ApiCache.instance.getStale<int>('nope'), isNull);
    });

    test('fetchWithCache calls the fetcher exactly once on cold cache', () async {
      var calls = 0;
      Future<int> fetch() async => ++calls;
      final v1 = await ApiCache.instance
          .fetchWithCache('k', fetch, const Duration(seconds: 5));
      final v2 = await ApiCache.instance
          .fetchWithCache('k', fetch, const Duration(seconds: 5));
      expect(v1, 1);
      expect(v2, 1, reason: 'second hit should serve from cache');
      expect(calls, 1);
    });

    test('fetchWithCache returns stale data immediately, revalidates async', () async {
      ApiCache.instance.set('k', 'stale', const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      var fetched = false;
      Future<String> fetch() async {
        fetched = true;
        return 'fresh';
      }

      final v = await ApiCache.instance
          .fetchWithCache('k', fetch, const Duration(seconds: 5));
      expect(v, 'stale', reason: 'caller sees the stale value first');
      // Background revalidation runs after the await chain — wait for it.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fetched, isTrue);
      expect(ApiCache.instance.get<String>('k'), 'fresh');
    });

    test('fetchWithCache(forceRefresh: true) bypasses the cache', () async {
      ApiCache.instance.set('k', 'old', const Duration(seconds: 5));
      var calls = 0;
      Future<String> fetch() async {
        calls++;
        return 'forced';
      }

      final v = await ApiCache.instance.fetchWithCache(
        'k',
        fetch,
        const Duration(seconds: 5),
        forceRefresh: true,
      );
      expect(v, 'forced');
      expect(calls, 1);
    });
  });

  group('invalidation', () {
    test('invalidate(key) removes one entry only', () {
      ApiCache.instance.set('a', 1, const Duration(seconds: 5));
      ApiCache.instance.set('b', 2, const Duration(seconds: 5));
      ApiCache.instance.invalidate('a');
      expect(ApiCache.instance.get<int>('a'), isNull);
      expect(ApiCache.instance.get<int>('b'), 2);
    });

    test('invalidatePrefix removes everything matching the prefix', () {
      ApiCache.instance.set('cat_live_alice', 1, const Duration(seconds: 5));
      ApiCache.instance.set('cat_vod_alice', 2, const Duration(seconds: 5));
      ApiCache.instance.set('streams_live_alice', 3, const Duration(seconds: 5));
      ApiCache.instance.invalidatePrefix('cat_');
      expect(ApiCache.instance.get<int>('cat_live_alice'), isNull);
      expect(ApiCache.instance.get<int>('cat_vod_alice'), isNull);
      expect(ApiCache.instance.get<int>('streams_live_alice'), 3);
    });

    test('invalidateForAccount removes everything containing the identifier', () {
      ApiCache.instance.set('cat_live_alice@host', 1, const Duration(seconds: 5));
      ApiCache.instance.set('cat_live_bob@host', 2, const Duration(seconds: 5));
      ApiCache.instance.invalidateForAccount('alice@host');
      expect(ApiCache.instance.get<int>('cat_live_alice@host'), isNull);
      expect(ApiCache.instance.get<int>('cat_live_bob@host'), 2);
    });

    test('clear() empties the whole cache', () {
      ApiCache.instance.set('a', 1, const Duration(seconds: 5));
      ApiCache.instance.set('b', 2, const Duration(seconds: 5));
      ApiCache.instance.clear();
      expect(ApiCache.instance.length, 0);
    });

    test('cleanup() drops only expired entries', () async {
      ApiCache.instance.set('keep', 1, const Duration(seconds: 5));
      ApiCache.instance.set('drop', 2, const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ApiCache.instance.cleanup();
      expect(ApiCache.instance.get<int>('keep'), 1);
      expect(ApiCache.instance.get<int>('drop'), isNull);
    });
  });
}
