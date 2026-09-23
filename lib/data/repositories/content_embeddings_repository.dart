import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'content_embeddings_repository.g.dart';

/// One catalogue item queued for embedding: its id/type plus the text
/// the vector should be built from (title + genre + themes + mood).
typedef EmbeddingInput = ({int streamId, String type, String text});

/// A loaded vector ready for local cosine similarity.
typedef EmbeddingVec = ({int streamId, String type, Float32List vector});

/// Read/write access to [ContentEmbeddings] — the semantic vectors
/// that power offline similarity / search. Vectors are L2-normalised
/// on write so similarity is a plain dot product at query time.
class ContentEmbeddingsRepository {
  final AppDatabase _db;

  ContentEmbeddingsRepository(this._db);

  // ── Encoding helpers ─────────────────────────────────────────────────────

  static Uint8List encode(Float32List v) => v.buffer.asUint8List();

  static Float32List decode(Uint8List bytes) {
    // Copy into an aligned buffer — Drift may hand back a view whose
    // offset isn't 4-byte aligned, which Float32List.view rejects.
    final copy = Uint8List.fromList(bytes);
    return copy.buffer.asFloat32List();
  }

  /// L2-normalise in place and return — lets cosine == dot product.
  static Float32List normalize(List<double> raw) {
    var sum = 0.0;
    for (final x in raw) {
      sum += x * x;
    }
    final norm = sum <= 0 ? 1.0 : 1.0 / (sqrtApprox(sum));
    final out = Float32List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      out[i] = raw[i] * norm;
    }
    return out;
  }

  // dart:math is unavailable in some build contexts here; a tiny
  // Newton sqrt is plenty for normalisation.
  static double sqrtApprox(double x) {
    if (x <= 0) return 0;
    var g = x;
    for (var i = 0; i < 20; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  Future<void> storeBatch(List<ContentEmbeddingsCompanion> rows) async {
    if (rows.isEmpty) return;
    await _db.accountBatch((batch) {
      for (final r in rows) {
        batch.insert(_db.contentEmbeddings, r,
            mode: InsertMode.insertOrReplace);
      }
    });
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Every stored vector, decoded. Loaded on demand for a search /
  /// similarity pass and discarded after — not held resident.
  Future<List<EmbeddingVec>> loadAll({String? type}) async {
    final q = _db.select(_db.contentEmbeddings);
    if (type != null) q.where((t) => t.type.equals(type));
    final rows = await q.get();
    return [
      for (final r in rows)
        (streamId: r.streamId, type: r.type, vector: decode(r.vector))
    ];
  }

  Future<Float32List?> lookup(int streamId, String type) async {
    final row = await (_db.select(_db.contentEmbeddings)
          ..where((t) => t.streamId.equals(streamId) & t.type.equals(type))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : decode(row.vector);
  }

  /// Items that should be embedded next: VOD with NO embedding yet that
  /// already has a usable text signal — either a provider genre or an
  /// enrichment row. Items with neither wait for the enrichment runner
  /// so we don't embed bare titles. Newest-first.
  Future<List<EmbeddingInput>> pendingItems({int limit = 64}) async {
    final c = _db.channels;
    final e = _db.contentEnrichment;
    final em = _db.contentEmbeddings;
    final rows = await (_db.select(c).join([
      _db.accountLeftJoin(e, e.streamId.equalsExp(c.streamId) & e.type.equalsExp(c.type)),
      _db.accountLeftJoin(em, em.streamId.equalsExp(c.streamId) & em.type.equalsExp(c.type)),
    ])
          ..where((c.type.equals('movie') | c.type.equals('series')) &
              em.streamId.isNull() &
              ((c.genre.isNotNull() & c.genre.equals('').not()) |
                  (c.plot.isNotNull() & c.plot.equals('').not()) |
                  e.streamId.isNotNull()))
          ..orderBy([OrderingTerm(expression: c.added, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
    final out = <EmbeddingInput>[];
    for (final r in rows) {
      final ch = r.readTable(c);
      final en = r.readTableOrNull(e);
      out.add((
        streamId: ch.streamId,
        type: ch.type,
        text: _buildText(ch, en),
      ));
    }
    return out;
  }

  Future<int> pendingCount() async {
    final c = _db.channels;
    final e = _db.contentEnrichment;
    final em = _db.contentEmbeddings;
    final countExpr = c.streamId.count();
    final q = _db.selectOnly(c).join([
      _db.accountLeftJoin(e, e.streamId.equalsExp(c.streamId) & e.type.equalsExp(c.type)),
      _db.accountLeftJoin(em, em.streamId.equalsExp(c.streamId) & em.type.equalsExp(c.type)),
    ])
      ..addColumns([countExpr])
      ..where((c.type.equals('movie') | c.type.equals('series')) &
          em.streamId.isNull() &
          ((c.genre.isNotNull() & c.genre.equals('').not()) |
              (c.plot.isNotNull() & c.plot.equals('').not()) |
              e.streamId.isNotNull()));
    final row = await q.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<int> embeddedCount() async {
    final countExpr = _db.contentEmbeddings.streamId.count();
    final q = _db.selectOnly(_db.contentEmbeddings)..addColumns([countExpr]);
    final row = await q.getSingle();
    return row.read(countExpr) ?? 0;
  }

  String _buildText(Channel ch, ContentEnrichmentData? en) {
    final genre = (ch.genre != null && ch.genre!.isNotEmpty)
        ? ch.genre
        : en?.genres;
    final year = (ch.year != null && ch.year!.isNotEmpty)
        ? ch.year
        : en?.year?.toString();
    // Plot/cast/director are the signals that make a vector
    // *per-title* distinctive. Without them, two series that share a
    // generic provider genre ("Drama") collapse onto nearly the same
    // vector and the "similar" rail returns the same handful for
    // everything. The plot in particular is the richest free-text
    // signal and is present on Xtream series rows.
    final plot = ch.plot?.trim();
    final director = ch.director?.trim();
    final cast = ch.cast?.trim();
    final parts = <String>[
      ch.name,
      if (genre != null && genre.isNotEmpty) genre,
      if (en?.themes != null && en!.themes!.isNotEmpty) en.themes!,
      if (en?.moodTags != null && en!.moodTags!.isNotEmpty) en.moodTags!,
      if (director != null && director.isNotEmpty) 'Director: $director',
      if (cast != null && cast.isNotEmpty) 'Cast: ${_firstCsv(cast, 6)}',
      if (plot != null && plot.isNotEmpty) _truncate(plot, 600),
      if (year != null && year.isNotEmpty) year,
    ];
    return parts.join('. ');
  }

  /// First [n] comma-separated values (e.g. top-billed cast) so a long
  /// 30-name cast list doesn't dominate the vector.
  static String _firstCsv(String csv, int n) {
    final parts = csv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(n)
        .toList();
    return parts.join(', ');
  }

  /// Hard length cap on the plot so one verbose synopsis can't swamp
  /// the embedding (the model truncates anyway; this keeps batches
  /// well under the input cap and the signal balanced).
  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// Wipe every stored vector. Used for a one-time rebuild when the
  /// embedding *text recipe* changes (otherwise old weak vectors stick
  /// around forever and the similar rail never improves).
  Future<int> clearAll() async {
    return _db.delete(_db.contentEmbeddings).go();
  }
}

@Riverpod(keepAlive: true)
ContentEmbeddingsRepository contentEmbeddingsRepository(Ref ref) {
  return ContentEmbeddingsRepository(ref.watch(appDatabaseProvider));
}
