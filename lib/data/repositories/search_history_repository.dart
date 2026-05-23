import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_history_repository.g.dart';

/// Read / write helpers for the [SearchHistory] Drift table.
///
/// "Recent" is `lastUsedAt DESC` (last-typed query first).
/// "Trending" is `useCount DESC` filtered to the last 7 days — gives
/// the user a view of what they've been searching for repeatedly
/// without surfacing one-off curiosity queries.
///
/// All writes are upserts on the composite PK (`query`) so a re-search
/// of the same term collapses into one row with an incremented
/// `useCount` and refreshed `lastUsedAt`. A cap of [_maxRows] keeps
/// the table from growing without bound on power users.
class SearchHistoryRepository {
  static const int _maxRows = 200;
  static const Duration _trendingWindow = Duration(days: 7);

  final AppDatabase _db;

  SearchHistoryRepository(this._db);

  /// Normalise to a stable form for the PK. Trims, lower-cases, and
  /// collapses runs of whitespace. The original query is also passed
  /// to the search engine; this normalised form is only used as a
  /// lookup key here and on the chip label.
  static String normalise(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  /// Record a search submission. Upserts the row, refreshes
  /// `lastUsedAt`, increments `useCount`, and prunes the table if
  /// it has crept past the cap.
  ///
  /// Caller should only invoke this for *intentional* searches —
  /// not on every keystroke. Use a submit handler on the search
  /// field's `onSubmitted` or after a debounce, otherwise the
  /// history fills with prefixes like "k", "ko", "kor", "kore".
  Future<void> record(String query) async {
    final normalised = normalise(query);
    if (normalised.isEmpty || normalised.length < 2) return;

    final existing = await (_db.select(_db.searchHistory)
          ..where((t) => t.query.equals(normalised))
          ..limit(1))
        .getSingleOrNull();

    if (existing == null) {
      await _db.into(_db.searchHistory).insert(
            SearchHistoryCompanion.insert(
              query: normalised,
              lastUsedAt: Value(DateTime.now()),
              useCount: const Value(1),
            ),
          );
    } else {
      await (_db.update(_db.searchHistory)
            ..where((t) => t.query.equals(normalised)))
          .write(SearchHistoryCompanion(
        lastUsedAt: Value(DateTime.now()),
        useCount: Value(existing.useCount + 1),
      ));
    }

    await _pruneIfNeeded();
  }

  /// Recent queries, last-used first. Capped to [limit] — the chip
  /// row only shows ~8.
  Future<List<String>> recent({int limit = 8}) async {
    final rows = await (_db.select(_db.searchHistory)
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.lastUsedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows.map((r) => r.query).toList();
  }

  /// Trending queries — anything submitted in the last 7 days,
  /// ordered by `useCount`. Useful when the user has used a phrase
  /// repeatedly recently ("kore dizisi", "tarkovsky") so they can
  /// pull it back with one tap.
  Future<List<String>> trending({int limit = 6}) async {
    final cutoff = DateTime.now().subtract(_trendingWindow);
    final rows = await (_db.select(_db.searchHistory)
          ..where((t) => t.lastUsedAt.isBiggerThanValue(cutoff))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.useCount, mode: OrderingMode.desc),
            (t) => OrderingTerm(
                expression: t.lastUsedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    // Drop entries that have only been used once — they don't belong
    // in a "trending" rail. The SQL already orders by useCount so this
    // is a cheap secondary filter.
    return rows.where((r) => r.useCount > 1).map((r) => r.query).toList();
  }

  /// Wipe everything. Wired into the Settings → Privacy panel and
  /// the search screen's "Geçmişi temizle" chip.
  Future<void> clearAll() async {
    await _db.delete(_db.searchHistory).go();
  }

  /// Remove one row. Wired into the long-press menu on each chip.
  Future<void> remove(String query) async {
    final normalised = normalise(query);
    await (_db.delete(_db.searchHistory)
          ..where((t) => t.query.equals(normalised)))
        .go();
  }

  /// Cap the table at [_maxRows]. Deletes the oldest-by-lastUsedAt
  /// rows past the cap. Called lazily after each insert/upsert so we
  /// don't need a background job.
  Future<void> _pruneIfNeeded() async {
    final count = await _db
        .customSelect('SELECT COUNT(*) AS c FROM search_history')
        .getSingle();
    final total = count.data['c'] as int? ?? 0;
    if (total <= _maxRows) return;
    // Delete the oldest (total - _maxRows) rows.
    final overflow = total - _maxRows;
    final toDelete = await (_db.select(_db.searchHistory)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.lastUsedAt, mode: OrderingMode.asc),
          ])
          ..limit(overflow))
        .get();
    final keys = toDelete.map((r) => r.query).toList();
    if (keys.isEmpty) return;
    await (_db.delete(_db.searchHistory)
          ..where((t) => t.query.isIn(keys)))
        .go();
  }
}

@riverpod
SearchHistoryRepository searchHistoryRepository(Ref ref) {
  return SearchHistoryRepository(ref.watch(appDatabaseProvider));
}

/// Live recent queries — search screen chip row watches this so a
/// new entry appears the moment it's recorded.
@riverpod
Future<List<String>> recentSearches(Ref ref) async {
  // Watch the table so any insert / delete invalidates the provider.
  // Drift's `select(...).watch()` is the canonical way but providers
  // here use one-shot fetch + ref.invalidate-on-write semantics; the
  // search screen calls `ref.invalidate(recentSearchesProvider)`
  // explicitly after recording a new query, which keeps this simple.
  return ref.watch(searchHistoryRepositoryProvider).recent();
}

@riverpod
Future<List<String>> trendingSearches(Ref ref) async {
  return ref.watch(searchHistoryRepositoryProvider).trending();
}
