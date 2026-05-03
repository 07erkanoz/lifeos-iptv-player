import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'watchlist_repository.g.dart';

/// "Save for later" / planned-watch list. Distinct from FavoritesRepository:
///  - Favorites = "I love this, give me quick access"
///  - Watchlist = "I plan to watch this, remind me later"
class WatchlistRepository {
  final AppDatabase _db;

  WatchlistRepository(this._db);

  /// Add an item to the watchlist (idempotent).
  Future<void> add(int streamId, String type, String name, String? thumbnail) async {
    await _db.into(_db.watchlist).insertOnConflictUpdate(
      WatchlistCompanion.insert(
        streamId: streamId,
        streamType: type,
        name: name,
        thumbnail: Value(thumbnail),
      ),
    );
  }

  /// Remove an item from the watchlist.
  Future<void> remove(int streamId, String type) async {
    await (_db.delete(_db.watchlist)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).go();
  }

  /// Toggle and return the new state (true = now in watchlist).
  Future<bool> toggle(int streamId, String type, String name, String? thumbnail) async {
    final existing = await (_db.select(_db.watchlist)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).getSingleOrNull();

    if (existing != null) {
      await remove(streamId, type);
      return false;
    }
    await add(streamId, type, name, thumbnail);
    return true;
  }

  /// Reactive: is this specific channel currently in the watchlist?
  Stream<bool> watchIsInWatchlist(int streamId, String type) {
    return (_db.select(_db.watchlist)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).watchSingleOrNull().map((row) => row != null);
  }

  /// All watchlist entries, newest-first.
  Stream<List<WatchlistData>> watchAll() {
    return (_db.select(_db.watchlist)
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.addedAt, mode: OrderingMode.desc)])
    ).watch();
  }

  /// Watchlist entries filtered by content type, newest-first.
  Stream<List<WatchlistData>> watchByType(String type) {
    return (_db.select(_db.watchlist)
      ..where((tbl) => tbl.streamType.equals(type))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.addedAt, mode: OrderingMode.desc)])
    ).watch();
  }

  /// Watchlist stream IDs of a given type — used for category filtering.
  Stream<List<int>> watchStreamIds(String type) {
    return watchByType(type).map((rows) => rows.map((r) => r.streamId).toList());
  }
}

@riverpod
WatchlistRepository watchlistRepository(Ref ref) {
  return WatchlistRepository(ref.watch(appDatabaseProvider));
}
