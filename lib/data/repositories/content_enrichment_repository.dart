import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'content_enrichment_repository.g.dart';

/// Read/write access to the [ContentEnrichment] table — AI-derived
/// genre / year / mood / themes for catalogue items whose provider
/// metadata is sparse.
///
/// The enrichment is produced once in the background (see the
/// catalogue-enrichment runner) and consumed as a fallback by
/// search / similar / the dashboard AI rails through
/// `ContentRepository`.
class ContentEnrichmentRepository {
  final AppDatabase _db;

  ContentEnrichmentRepository(this._db);

  /// Single lookup. Null when the item hasn't been enriched yet.
  Future<ContentEnrichmentData?> lookup(int streamId, String type) {
    return (_db.select(_db.contentEnrichment)
          ..where((t) => t.streamId.equals(streamId) & t.type.equals(type))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Bulk lookup keyed by `"streamId|type"` so callers can merge a
  /// whole candidate list in one query instead of N round-trips.
  Future<Map<String, ContentEnrichmentData>> lookupMany(
    Iterable<({int streamId, String type})> keys,
  ) async {
    final ids = keys.map((k) => k.streamId).toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await (_db.select(_db.contentEnrichment)
          ..where((t) => t.streamId.isIn(ids)))
        .get();
    return {for (final r in rows) '${r.streamId}|${r.type}': r};
  }

  /// Write-through upsert for a batch of enrichment results.
  Future<void> storeBatch(List<ContentEnrichmentCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.contentEnrichment, r,
            mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// Candidate items that still need enrichment: VOD with an empty
  /// `genre` column and no existing enrichment row. Newest-first (by
  /// the Xtream `added` timestamp) so freshly-added titles — the ones
  /// users actually browse — get enriched first.
  Future<List<Channel>> pendingItems({int limit = 40}) async {
    final query = _db.select(_db.channels).join([
      leftOuterJoin(
        _db.contentEnrichment,
        _db.contentEnrichment.streamId.equalsExp(_db.channels.streamId) &
            _db.contentEnrichment.type.equalsExp(_db.channels.type),
      ),
    ])
      ..where((_db.channels.type.equals('movie') |
              _db.channels.type.equals('series')) &
          _db.contentEnrichment.streamId.isNull() &
          (_db.channels.genre.isNull() |
              _db.channels.genre.equals('')))
      ..orderBy([
        OrderingTerm(expression: _db.channels.added, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(_db.channels)).toList();
  }

  /// How many VOD items still lack genre + enrichment. Drives the
  /// runner's "is there work left?" loop and a Settings progress hint.
  Future<int> pendingCount() async {
    final countExpr = _db.channels.streamId.count();
    final query = _db.selectOnly(_db.channels).join([
      leftOuterJoin(
        _db.contentEnrichment,
        _db.contentEnrichment.streamId.equalsExp(_db.channels.streamId) &
            _db.contentEnrichment.type.equalsExp(_db.channels.type),
      ),
    ])
      ..addColumns([countExpr])
      ..where((_db.channels.type.equals('movie') |
              _db.channels.type.equals('series')) &
          _db.contentEnrichment.streamId.isNull() &
          (_db.channels.genre.isNull() |
              _db.channels.genre.equals('')));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }
}

@Riverpod(keepAlive: true)
ContentEnrichmentRepository contentEnrichmentRepository(Ref ref) {
  return ContentEnrichmentRepository(ref.watch(appDatabaseProvider));
}
