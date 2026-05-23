import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_repository.g.dart';

/// Per-profile favourites store.
///
/// Every read and write filters by the active profile id obtained
/// from the [_getActiveProfileId] callback. The repository itself
/// is stateless w.r.t. the active id — it asks on every call so a
/// runtime profile switch is reflected without re-creating the
/// instance. Provider wiring at the bottom passes a closure that
/// reads activeProfileIdProvider; callers never have to plumb the
/// id through method args, which keeps existing UI code identical.
class FavoritesRepository {
  final AppDatabase _db;
  final int Function() _getActiveProfileId;

  FavoritesRepository(this._db, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  /// Add to favorites
  Future<void> addFavorite(int streamId, String type, String name, String? thumbnail) async {
    await _db.into(_db.favorites).insertOnConflictUpdate(
      FavoritesCompanion.insert(
        streamId: streamId,
        streamType: type,
        name: name,
        thumbnail: Value(thumbnail),
        profileId: Value(_pid),
      ),
    );
  }

  /// Remove from favorites
  Future<void> removeFavorite(int streamId, String type) async {
    await (_db.delete(_db.favorites)
      ..where((tbl) =>
          tbl.streamId.equals(streamId) &
          tbl.streamType.equals(type) &
          tbl.profileId.equals(_pid))
    ).go();
  }

  /// Toggle favorite state
  Future<bool> toggleFavorite(int streamId, String type, String name, String? thumbnail) async {
    final existing = await (_db.select(_db.favorites)
      ..where((tbl) =>
          tbl.streamId.equals(streamId) &
          tbl.streamType.equals(type) &
          tbl.profileId.equals(_pid))
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
      ..where((tbl) =>
          tbl.streamId.equals(streamId) &
          tbl.streamType.equals(type) &
          tbl.profileId.equals(_pid))
    ).watchSingleOrNull().map((row) => row != null);
  }

  /// Watch all favorites of a specific type
  Stream<List<Favorite>> watchFavoritesByType(String type) {
    return (_db.select(_db.favorites)
      ..where((tbl) =>
          tbl.streamType.equals(type) & tbl.profileId.equals(_pid))
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
      ..where((tbl) => tbl.profileId.equals(_pid))
      ..orderBy([(tbl) => OrderingTerm(expression: tbl.addedAt, mode: OrderingMode.desc)])
    ).watch();
  }
}

@riverpod
FavoritesRepository favoritesRepository(Ref ref) {
  // Watch the active id so when the user switches profiles every
  // FavoritesRepository consumer rebuilds against the new id. The
  // closure read inside the repo always returns the freshest value.
  ref.watch(activeProfileIdProvider);
  return FavoritesRepository(
    ref.watch(appDatabaseProvider),
    () => ref.read(activeProfileIdProvider).value ?? 1,
  );
}
