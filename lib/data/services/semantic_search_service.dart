import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';

/// A ranked semantic match.
typedef SemanticHit = ({int streamId, String type, double score});

/// Local semantic retrieval over the [ContentEmbeddings] table.
///
/// Vectors are L2-normalised on write, so cosine similarity is just a
/// dot product. Everything here runs on-device — `similarTo` needs no
/// network at all; `search` makes a single cheap embedding call for
/// the query and then ranks locally.
class SemanticSearchService {
  final ContentEmbeddingsRepository _repo;
  final GeminiService? _gemini;

  SemanticSearchService(this._repo, this._gemini);

  /// Each worker ranks a bounded page and returns only its best k results.
  /// No model/repository/DB handle is captured by the worker closure.
  static List<SemanticHit> rankPage(
    Float32List query,
    List<EmbeddingVec> page,
    int k,
    int? excludeStreamId,
    String? excludeType,
  ) {
    if (k <= 0 || query.isEmpty || query.any((x) => !x.isFinite)) return [];
    final scored = <SemanticHit>[];
    for (final v in page) {
      if ((v.streamId == excludeStreamId && v.type == excludeType) ||
          v.vector.length != query.length)
        continue;
      var score = 0.0;
      for (var i = 0; i < query.length; i++) {
        score += query[i] * v.vector[i];
      }
      if (!score.isFinite) continue;
      scored.add((streamId: v.streamId, type: v.type, score: score));
    }
    scored.sort(compareHits);
    return scored.take(k).toList();
  }

  static int compareHits(SemanticHit a, SemanticHit b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final id = a.streamId.compareTo(b.streamId);
    return id != 0 ? id : a.type.compareTo(b.type);
  }

  Future<List<SemanticHit>> _rank(
    Float32List query, {
    required int k,
    String? restrictType,
    int? excludeStreamId,
    String? excludeType,
  }) async {
    if (k <= 0 || query.isEmpty) return [];
    final limit = k.clamp(1, 1000);
    var best = <SemanticHit>[];
    await for (final page in _repo.pages(type: restrictType)) {
      final hits = await Isolate.run(
        () => rankPage(query, page, limit, excludeStreamId, excludeType),
      );
      best = [...best, ...hits]..sort(compareHits);
      if (best.length > limit) best.length = limit;
    }
    return best;
  }

  /// Items most similar to a given catalogue item. Empty when the item
  /// hasn't been embedded yet (caller falls back to its heuristic).
  Future<List<SemanticHit>> similarTo(
    int streamId,
    String type, {
    int k = 40,
    String? restrictType,
  }) async {
    final anchor = await _repo.lookup(streamId, type);
    if (anchor == null) return const [];
    return _rank(
      anchor,
      restrictType: restrictType ?? type,
      k: k,
      excludeStreamId: streamId,
      excludeType: type,
    );
  }

  /// Free-text semantic search. Embeds [query] once, ranks locally.
  /// Empty when there's no key or nothing embedded yet.
  Future<List<SemanticHit>> search(
    String query, {
    int k = 60,
    String? restrictType,
  }) async {
    final gemini = _gemini;
    if (gemini == null || query.trim().isEmpty) return const [];
    final raw = await gemini.embedTexts(
      [query],
      dims: 768,
      retrievalQuery: true,
    );
    if (raw == null || raw.isEmpty || raw.first.isEmpty) return const [];
    final q = ContentEmbeddingsRepository.normalize(raw.first);
    return _rank(q, restrictType: restrictType, k: k);
  }
}

final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(
    ref.watch(contentEmbeddingsRepositoryProvider),
    ref.watch(geminiServiceProvider),
  );
});
