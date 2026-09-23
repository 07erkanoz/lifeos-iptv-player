import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'personalized_picks_repository.g.dart';

/// One pick from the "Sana Özel" rail — paired stream-id + AI
/// reason. Kept as a record so it round-trips through JSON cleanly
/// when we serialise the cache row.
typedef PersonalizedPick = ({int streamId, String reason});

/// Persistent cache for the dashboard "Sana Özel" rail.
///
/// Singleton table — one row keyed by id=0. The dashboard reads
/// this on every build and decides whether to refresh based on
/// age and a source-state fingerprint.
///
/// Staleness rules:
///   * `generatedAt` older than [ttl] (default 12 h) → refresh.
///   * `sourceHash` mismatch (user has new watch history or
///     toggled favourites enough that the previous picks reflect
///     a stale snapshot) → refresh.
class PersonalizedPicksRepository {
  final AppDatabase _db;

  PersonalizedPicksRepository(this._db);

  /// Bumped whenever the system prompt or response budget in
  /// [GeminiService.recommendForYou] changes — old cache rows
  /// produced under a previous prompt become stale automatically
  /// because the version is folded into [fingerprint].
  static const _promptVersion = 'v1';

  /// Read the cached picks. Returns `null` when the row doesn't
  /// exist, is older than [ttl], or its source fingerprint no
  /// longer matches the supplied [sourceHash].
  Future<List<PersonalizedPick>?> lookup({
    required String sourceHash,
    Duration ttl = const Duration(hours: 12),
  }) async {
    final row = await (_db.select(_db.personalizedPicksCache)
          ..where((t) => t.id.equals(0))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.sourceHash != sourceHash) return null;
    if (DateTime.now().difference(row.generatedAt) > ttl) return null;
    return _decodePicks(row.picksJson);
  }

  /// Return whatever row exists, regardless of [sourceHash] — as
  /// long as the row is younger than [maxAge].
  ///
  /// Used by the stale-while-revalidate path in the provider:
  /// when the user's taste signals have drifted since the cache
  /// was written (new history rows, favourites churn), the strict
  /// [lookup] above will miss, but a slightly-stale "Sana Özel"
  /// rail is still vastly better UX than a 5-15 second shimmer
  /// while a fresh Gemini call lands. The provider returns the
  /// stale row instantly and kicks off the fresh call in the
  /// background.
  Future<List<PersonalizedPick>?> lookupLatest({
    Duration maxAge = const Duration(days: 14),
  }) async {
    final row = await (_db.select(_db.personalizedPicksCache)
          ..where((t) => t.id.equals(0))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    if (DateTime.now().difference(row.generatedAt) > maxAge) return null;
    return _decodePicks(row.picksJson);
  }

  /// Upsert the singleton row.
  Future<void> store({
    required String sourceHash,
    required List<PersonalizedPick> picks,
  }) async {
    final encoded = jsonEncode(picks
        .map((p) => {'streamId': p.streamId, 'reason': p.reason})
        .toList());
    await _db.into(_db.personalizedPicksCache).insert(
          PersonalizedPicksCacheCompanion.insert(
            id: 0,
            picksJson: encoded,
            sourceHash: sourceHash,
            generatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Drop the cache. Hook for future "refresh" UI; auto-invalidation
  /// via hash + TTL already handles the common case.
  Future<void> clear() async {
    await (_db.delete(_db.personalizedPicksCache)
          ..where((t) => t.id.equals(0)))
        .go();
  }

  /// Fingerprint of (recently watched ids + favourite ids + feedback
  /// signals + prompt version). All lists are sorted before hashing
  /// so a logically-equivalent state produces the same fingerprint.
  ///
  /// Including the disliked / moreLike sets means flagging a title
  /// via the ⋯ menu auto-invalidates the cached rail — without it
  /// the rail would keep serving the pre-feedback row from cache
  /// until the user manually hit refresh.
  static String fingerprint({
    required Iterable<int> recentlyWatchedIds,
    required Iterable<int> favoriteIds,
    Iterable<int> dislikedIds = const [],
    Iterable<int> moreLikeIds = const [],
  }) {
    final r = recentlyWatchedIds.toList()..sort();
    final f = favoriteIds.toList()..sort();
    final d = dislikedIds.toList()..sort();
    final m = moreLikeIds.toList()..sort();
    final blob = '$_promptVersion'
        '|r=${r.join(",")}'
        '|f=${f.join(",")}'
        '|d=${d.join(",")}'
        '|m=${m.join(",")}';
    var h = 0x811c9dc5;
    for (final code in blob.codeUnits) {
      h = (h ^ code) & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  // ─── helpers ────────────────────────────────────────────────────

  List<PersonalizedPick> _decodePicks(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <PersonalizedPick>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final sidRaw = item['streamId'];
        int? sid;
        if (sidRaw is int) {
          sid = sidRaw;
        } else if (sidRaw is num) {
          sid = sidRaw.toInt();
        } else if (sidRaw != null) {
          sid = int.tryParse(sidRaw.toString());
        }
        final reason = item['reason']?.toString().trim() ?? '';
        if (sid != null && sid > 0 && reason.isNotEmpty) {
          out.add((streamId: sid, reason: reason));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

@riverpod
PersonalizedPicksRepository personalizedPicksRepository(Ref ref) {
  return PersonalizedPicksRepository(ref.watch(appDatabaseProvider));
}
