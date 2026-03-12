import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_repository.g.dart';

class FavoritesRepository {
  final AppDatabase _db;

  FavoritesRepository(this._db);

  /// Add to favorites
  Future<void> addFavorite(int streamId, String type, String name, String? thumbnail) async {
    await _db.into(_db.favorites).insertOnConflictUpdate(
      FavoritesCompanion.insert(
        streamId: streamId,
        streamType: type,
        name: name,
        thumbnail: Value(thumbnail),
      ),
    );
  }

  /// Remove from favorites
  Future<void> removeFavorite(int streamId, String type) async {
    await (_db.delete(_db.favorites)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).go();
  }

  /// Toggle favorite state
  Future<bool> toggleFavorite(int streamId, String type, String name, String? thumbnail) async {
    final existing = await (_db.select(_db.favorites)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).getSingleOrNull();

    if (existing != null) {
      await removeFavorite(streamId, type);
      return false; // removed
    } else {
      await addFavorite(streamId, type, name, thumbnail);
      return true; // added
    }
  }

  /// Watch if a specific channel is favorited
  Stream<bool> watchIsFavorite(int streamId, String type) {
    return (_db.select(_db.favorites)
      ..where((tbl) => tbl.streamId.equals(streamId) & tbl.streamType.equals(type))
    ).watchSingleOrNull().map((row) => row != null);
  }

  /// Watch all favorites of a specific type
  Stream<List<Favorite>> watchFavoritesByType(String type) {
    return (_db.select(_db.favorites)
      ..where((tbl) => tbl.streamType.equals(type))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.addedAt, mode: OrderingMode.desc)])
    ).watch();
  }

  /// Watch favorite stream IDs for a type (used for category filtering)
  Stream<List<int>> watchFavoriteStreamIds(String type) {
    return watchFavoritesByType(type).map((favs) => favs.map((f) => f.streamId).toList());
  }

  /// Watch all favorites
  Stream<List<Favorite>> watchAllFavorites() {
    return (_db.select(_db.favorites)
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.addedAt, mode: OrderingMode.desc)])
    ).watch();
  }
}

@riverpod
FavoritesRepository favoritesRepository(Ref ref) {
  return FavoritesRepository(ref.watch(appDatabaseProvider));
}
