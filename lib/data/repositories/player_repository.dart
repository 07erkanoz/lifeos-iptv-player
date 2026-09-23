import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'player_repository.g.dart';

class PlayerRepository {
  final AppDatabase _db;
  final int Function() _getActiveProfileId;

  PlayerRepository(this._db, this._getActiveProfileId);

  int get _pid => _getActiveProfileId();

  Future<void> saveProgress(
    int streamId,
    String type,
    int position,
    int duration,
  ) async {
    if (duration <= 0 || position < 0) return;
    final boundedPosition = position.clamp(0, duration);
    final isFinished = (boundedPosition / duration) > 0.95;

    await _db
        .into(_db.playbackProgress)
        .insert(
          PlaybackProgressCompanion.insert(
            streamId: streamId,
            type: type,
            position: boundedPosition,
            duration: duration,
            isFinished: Value(isFinished),
            updatedAt: Value(DateTime.now()),
            profileId: Value(_pid),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Series channel IDs and episode IDs are different namespaces at Xtream.
  /// Never mirror a series summary into another episode's resume record.
  Future<void> saveEpisodeProgress(
    int episodeId,
    int position,
    int duration, {
    int? parentSeriesId,
  }) async {
    if (duration <= 0 || position < 0) return;
    final pid = _pid, bounded = position.clamp(0, duration);
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.accountBatch((batch) {
        for (final identity in [
          (episodeId, 'series'),
          if (parentSeriesId != null) (parentSeriesId, 'series_parent'),
        ]) {
          batch.insert(
            _db.playbackProgress,
            PlaybackProgressCompanion.insert(
              streamId: identity.$1,
              type: identity.$2,
              position: bounded,
              duration: duration,
              isFinished: Value(bounded / duration > 0.95),
              updatedAt: Value(now),
              profileId: Value(pid),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  Future<PlaybackProgressData?> getProgress(int streamId, String type) async {
    return await (_db.select(_db.playbackProgress)..where(
          (tbl) =>
              tbl.streamId.equals(streamId) &
              tbl.type.equals(type) &
              tbl.profileId.equals(_pid),
        ))
        .getSingleOrNull();
  }

  /// Get the most recently watched episode from a list of episode IDs,
  /// regardless of whether it was finished or not.
  ///
  /// The previous implementation filtered to `isFinished == false`, which
  /// gave wrong "Continue Watching" suggestions when a user had a stale
  /// partially-watched episode followed by several fully-watched ones:
  /// the partial would surface even though the user had since finished
  /// later episodes. Callers can inspect `isFinished` on the returned
  /// row and decide whether to resume mid-episode or advance to the
  /// next one.
  Future<PlaybackProgressData?> getLatestSeriesProgress(
    List<int> episodeIds,
  ) async {
    final ids = episodeIds.toSet().toList(), pid = _pid;
    PlaybackProgressData? newest;
    for (var i = 0; i < ids.length; i += 500) {
      final row =
          await (_db.select(_db.playbackProgress)
                ..where(
                  (t) =>
                      t.streamId.isIn(ids.skip(i).take(500)) &
                      t.type.equals('series') &
                      t.profileId.equals(pid) &
                      t.position.isBiggerThanValue(0),
                )
                ..orderBy([
                  (t) => OrderingTerm.desc(t.updatedAt),
                  (t) => OrderingTerm.desc(t.streamId),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (row != null &&
          (newest == null ||
              row.updatedAt.isAfter(newest.updatedAt) ||
              row.updatedAt == newest.updatedAt &&
                  row.streamId > newest.streamId)) {
        newest = row;
      }
    }
    return newest;
  }

  /// Remove a single item from history
  Future<void> deleteProgress(int streamId, String type) async {
    await (_db.delete(_db.playbackProgress)..where(
          (tbl) =>
              tbl.streamId.equals(streamId) &
              tbl.type.equals(type) &
              tbl.profileId.equals(_pid),
        ))
        .go();
  }

  /// Hide a series summary without deleting a numerically equal episode.
  /// The zero-position summary also suppresses an ambiguous legacy mirror.
  Future<void> removeSeriesFromHistory(int seriesId) =>
      saveProgress(seriesId, 'series_parent', 0, 1);

  /// Clear all history for a given type (movie/series/live) on the
  /// active profile only. The "clear history" UI never crosses
  /// profile boundaries.
  Future<void> clearAllProgress(String type) async {
    await (_db.delete(_db.playbackProgress)..where(
          (tbl) =>
              tbl.type.isIn(
                type == 'series' ? ['series', 'series_parent'] : [type],
              ) &
              tbl.profileId.equals(_pid),
        ))
        .go();
  }

  /// Bulk-mark a batch of episodes as watched (isFinished = true).
  /// Used by the "Mark season as watched" action — the user selects
  /// a whole season tab and one tap marks every episode in it. We
  /// use upsert semantics (insertOrReplace on the composite
  /// (streamId, type) PK) so this works whether or not the user had
  /// any prior partial progress on those episodes.
  ///
  /// `position`/`duration` are set to a sentinel "watched-to-end"
  /// value (1 / 1) so the existing >95% finished check stays
  /// consistent, and the row sorts to the bottom of "Continue
  /// Watching" rather than re-appearing as a half-watched item.
  Future<void> markEpisodesAsWatched(List<int> streamIds) async {
    if (streamIds.isEmpty) return;
    final now = DateTime.now();
    final pid = _pid;
    await _db.accountBatch((batch) {
      for (final id in streamIds) {
        batch.insert(
          _db.playbackProgress,
          PlaybackProgressCompanion.insert(
            streamId: id,
            type: 'series',
            position: 1,
            duration: 1,
            isFinished: const Value(true),
            updatedAt: Value(now),
            profileId: Value(pid),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Inverse of [markEpisodesAsWatched] — clear progress rows for a
  /// season the user wants to re-watch from scratch. Scoped to the
  /// active profile.
  Future<void> unmarkEpisodes(List<int> streamIds) async {
    final ids = streamIds.toSet().toList(), pid = _pid;
    await _db.transaction(() async {
      for (var i = 0; i < ids.length; i += 500) {
        await (_db.delete(_db.playbackProgress)..where(
              (t) =>
                  t.streamId.isIn(ids.skip(i).take(500)) &
                  t.type.equals('series') &
                  t.profileId.equals(pid),
            ))
            .go();
      }
    });
  }

  /// Count how many of the given episode ids are flagged as finished
  /// for the active profile.
  Future<int> finishedCount(List<int> streamIds) async {
    final ids = streamIds.toSet().toList(), pid = _pid;
    var count = 0;
    for (var i = 0; i < ids.length; i += 500) {
      final total = _db.playbackProgress.streamId.count();
      final row =
          await (_db.selectOnly(_db.playbackProgress)
                ..addColumns([total])
                ..where(
                  _db.playbackProgress.streamId.isIn(ids.skip(i).take(500)) &
                      _db.playbackProgress.type.equals('series') &
                      _db.playbackProgress.isFinished.equals(true) &
                      _db.playbackProgress.profileId.equals(pid),
                ))
              .getSingle();
      count += row.read(total) ?? 0;
    }
    return count;
  }
}

@riverpod
PlayerRepository playerRepository(Ref ref) {
  final profileId = ref.watch(activeProfileIdProvider).value ?? 1;
  return PlayerRepository(ref.watch(appDatabaseProvider), () => profileId);
}
