import 'dart:typed_data';

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

  static double _dot(Float32List a, Float32List b) {
    final n = a.length < b.length ? a.length : b.length;
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  List<SemanticHit> _rank(
    Float32List query,
    List<EmbeddingVec> all, {
    required int k,
    int? excludeStreamId,
    String? excludeType,
  }) {
    final scored = <SemanticHit>[];
    for (final v in all) {
      if (v.streamId == excludeStreamId && v.type == excludeType) continue;
      scored.add((streamId: v.streamId, type: v.type, score: _dot(query, v.vector)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.length > k ? scored.sublist(0, k) : scored;
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
    final all = await _repo.loadAll(type: restrictType ?? type);
    return _rank(anchor, all,
        k: k, excludeStreamId: streamId, excludeType: type);
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
    final raw = await gemini.embedTexts([query], dims: 768);
    if (raw == null || raw.isEmpty || raw.first.isEmpty) return const [];
    final q = ContentEmbeddingsRepository.normalize(raw.first);
    final all = await _repo.loadAll(type: restrictType);
    if (all.isEmpty) return const [];
    return _rank(q, all, k: k);
  }
}

final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(
    ref.watch(contentEmbeddingsRepositoryProvider),
    ref.watch(geminiServiceProvider),
  );
});
