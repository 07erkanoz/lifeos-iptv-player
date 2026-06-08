import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_similar_cache_repository.g.dart';

/// Persistent cache for the AI similar-content rail.
///
/// Without this, every detail-page open re-ran a 500-item Gemini
/// prompt (5-10 seconds on Flash 2.5). Most users reopen the same
/// titles repeatedly during a browse session, so a single Drift
/// lookup turns the second-and-subsequent opens into instant hits.
///
/// `sourceHash` covers the inputs that change the AI's answer
/// (current title id + the user's recent favourites for the type +
/// prompt version). A mismatch on read invalidates the row and the
/// caller falls through to a fresh fetch. Combined with a 7-day TTL
/// the rail stays fresh enough to react when the user's taste
/// shifts.
class AiSimilarCacheRepository {
  static const _ttl = Duration(days: 7);
  // v2: similar rail now blends an enrichment-aware semantic group and
  // feeds themes/mood into the Gemini prompt — old v1 rows were
  // genre-only, so invalidate them all by bumping the version.
  static const _promptVersion = 'v2';

  final AppDatabase _db;

  AiSimilarCacheRepository(this._db);

  /// Compute a stable fingerprint over the inputs that drive the AI
  /// prompt. Caller supplies the favourite ids; we sort + hash them
  /// alongside the current title so the cache key is identical for
  /// the same (title, taste) pair across sessions.
  static String fingerprint({
    required int streamId,
    required String type,
    required List<int> favouriteIds,
  }) {
    final sorted = [...favouriteIds]..sort();
    final joined =
        'v=$_promptVersion|s=$streamId|t=$type|f=${sorted.join(",")}';
    return _fnv1a32(joined);
  }

  /// Lookup. Returns null when:
  ///   * no row exists,
  ///   * row's [sourceHash] doesn't match the caller's fingerprint,
  ///   * row is older than [_ttl].
  ///
  /// Returns the decoded JSON payload on hit (the caller is
  /// responsible for re-hydrating it into typed models — keeping
  /// the cache layer payload-shape-agnostic).
  Future<List<dynamic>?> lookup({
    required int streamId,
    required String type,
    required String sourceHash,
  }) async {
    final row = await (_db.select(_db.aiSimilarCache)
          ..where((t) =>
              t.streamId.equals(streamId) & t.type.equals(type))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      debugPrint(
          '[similar-cache] MISS no row for streamId=$streamId type=$type');
      return null;
    }
    if (row.sourceHash != sourceHash) {
      debugPrint(
          '[similar-cache] MISS hash mismatch streamId=$streamId '
          'stored=${row.sourceHash} expected=$sourceHash');
      return null;
    }
    final age = DateTime.now().difference(row.generatedAt);
    if (age > _ttl) {
      debugPrint('[similar-cache] MISS expired streamId=$streamId '
          'age=${age.inHours}h');
      return null;
    }
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is List) {
        debugPrint('[similar-cache] HIT streamId=$streamId '
            'items=${decoded.length} age=${age.inMinutes}m');
        return decoded;
      }
      return null;
    } catch (e) {
      debugPrint('[similar-cache] MISS decode error: $e');
      return null;
    }
  }

  /// Write-through. Replaces any existing row for the same
  /// (streamId, type) key. Payload is JSON-encoded here so callers
  /// pass plain Dart lists / maps and never touch jsonEncode.
  Future<void> store({
    required int streamId,
    required String type,
    required String sourceHash,
    required List<dynamic> payload,
  }) async {
    try {
      await _db.into(_db.aiSimilarCache).insertOnConflictUpdate(
            AiSimilarCacheCompanion.insert(
              streamId: streamId,
              type: type,
              payloadJson: jsonEncode(payload),
              sourceHash: sourceHash,
              generatedAt: Value(DateTime.now()),
            ),
          );
      debugPrint('[similar-cache] WROTE streamId=$streamId type=$type '
          'items=${payload.length}');
    } catch (e) {
      debugPrint('[similar-cache] WRITE FAILED streamId=$streamId '
          'error=$e');
    }
  }

  /// FNV-1a 32-bit, same hash the personalized-picks cache uses.
  /// Cheap (no `dart:crypto`), stable, and produces a short
  /// hex string suitable as a TEXT column key.
  static String _fnv1a32(String input) {
    const int offset = 0x811c9dc5;
    const int prime = 0x01000193;
    var hash = offset;
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

@Riverpod(keepAlive: true)
AiSimilarCacheRepository aiSimilarCacheRepository(Ref ref) {
  return AiSimilarCacheRepository(ref.watch(appDatabaseProvider));
}
