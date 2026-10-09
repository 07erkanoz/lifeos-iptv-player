import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'intro_marker_repository.g.dart';

class IntroMarkerRepository {
  final AppDatabase _db;
  IntroMarkerRepository(this._db);

  // Drift stores DateTime in whole seconds. Local edits must advance even when
  // delete and re-create happen within one second or the peer clock is ahead.
  Future<DateTime> _nextTimestamp(
    int seriesId,
    int season,
    int episodeId,
  ) async {
    final query = _db.select(_db.introMarkers)
      ..where(
        (t) =>
            t.seriesId.equals(seriesId) &
            t.season.equals(season) &
            t.episodeId.equals(episodeId),
      );
    final old = await query.getSingleOrNull();
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final oldSeconds = old?.updatedAt.millisecondsSinceEpoch;
    final next = oldSeconds == null ? nowSeconds : oldSeconds ~/ 1000 + 1;
    return DateTime.fromMillisecondsSinceEpoch(
      (nowSeconds > next ? nowSeconds : next) * 1000,
    );
  }

  SimpleSelectStatement<$IntroMarkersTable, IntroMarker> _query(
    int seriesId,
    int season,
    int episodeId,
  ) => _db.select(_db.introMarkers)
    ..where(
      (t) =>
          t.seriesId.equals(seriesId) &
          t.season.equals(season) &
          (t.episodeId.equals(episodeId) | t.episodeId.equals(0)),
    )
    ..orderBy([(t) => OrderingTerm.desc(t.episodeId)]);

  IntroMarker? _pick(List<IntroMarker> rows) {
    if (rows.isEmpty || rows.first.isDeleted) return null;
    return rows.first;
  }

  Future<IntroMarker?> getMarker(
    int seriesId, {
    int season = 0,
    int episodeId = 0,
  }) async => _pick(await _query(seriesId, season, episodeId).get());
  Stream<IntroMarker?> watchMarker(
    int seriesId, {
    int season = 0,
    int episodeId = 0,
  }) => _query(seriesId, season, episodeId).watch().map(_pick);

  Future<void> setMarker(
    int seriesId, {
    required int introStartMs,
    required int introEndMs,
    int season = 0,
    int episodeId = 0,
    int? durationMs,
    String source = 'manual',
    double confidence = 1.0,
  }) async {
    if (seriesId < 0 ||
        season < 0 ||
        episodeId < 0 ||
        introStartMs < 0 ||
        introEndMs <= introStartMs ||
        (durationMs != null && introEndMs > durationMs) ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        !{'manual', 'chapters', 'legacy'}.contains(source)) {
      throw ArgumentError('Invalid intro marker');
    }
    await _db.transaction(() async {
      final updatedAt = await _nextTimestamp(seriesId, season, episodeId);
      await _db
          .into(_db.introMarkers)
          .insert(
            IntroMarkersCompanion.insert(
              seriesId: seriesId,
              season: Value(season),
              episodeId: Value(episodeId),
              introStartMs: introStartMs,
              introEndMs: introEndMs,
              source: Value(source),
              confidence: Value(confidence),
              updatedAt: Value(updatedAt),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }

  /// Keep a tombstone so a paired device cannot resurrect an older marker.
  Future<void> clearMarker(
    int seriesId, {
    int season = 0,
    int episodeId = 0,
  }) async {
    if (seriesId < 0 || season < 0 || episodeId < 0)
      throw ArgumentError('Invalid intro identity');
    await _db.transaction(() async {
      final updatedAt = await _nextTimestamp(seriesId, season, episodeId);
      await _db
          .into(_db.introMarkers)
          .insert(
            IntroMarkersCompanion.insert(
              seriesId: seriesId,
              season: Value(season),
              episodeId: Value(episodeId),
              introStartMs: 0,
              introEndMs: 1,
              isDeleted: const Value(true),
              updatedAt: Value(updatedAt),
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }

  Future<int> merge(List<Map<String, dynamic>> rows) async {
    var count = 0;
    await _db.transaction(() async {
      for (final row in rows) {
        try {
          final marker = IntroMarker.fromJson(row);
          if (marker.seriesId < 0 ||
              marker.season < 0 ||
              marker.episodeId < 0 ||
              marker.introStartMs < 0 ||
              marker.introEndMs <= marker.introStartMs ||
              !marker.confidence.isFinite ||
              marker.confidence < 0 ||
              marker.confidence > 1 ||
              !{'manual', 'chapters', 'legacy'}.contains(marker.source))
            continue;
          final query = _db.select(_db.introMarkers)
            ..where(
              (t) =>
                  t.seriesId.equals(marker.seriesId) &
                  t.season.equals(marker.season) &
                  t.episodeId.equals(marker.episodeId),
            );
          final old = await query.getSingleOrNull();
          if (old != null &&
              (marker.updatedAt.isBefore(old.updatedAt) ||
                  (marker.updatedAt.isAtSameMomentAs(old.updatedAt) &&
                      (!marker.isDeleted || old.isDeleted))))
            continue;
          await _db
              .into(_db.introMarkers)
              .insertOnConflictUpdate(
                marker.copyWith(accountId: _db.accountScope ?? 0),
              );
          count++;
        } catch (_) {
          /* Invalid peer row cannot abort valid markers. */
        }
      }
    });
    return count;
  }
}

@riverpod
IntroMarkerRepository introMarkerRepository(Ref ref) =>
    IntroMarkerRepository(ref.watch(appDatabaseProvider));
final introMarkerProvider = StreamProvider.family<IntroMarker?, int>(
  (ref, seriesId) =>
      ref.watch(introMarkerRepositoryProvider).watchMarker(seriesId),
);
