/// Aggregate, weighted view of "what does this user actually like".
///
/// Built from raw signals (history, favourites, completion ratios,
/// explicit ⋯-menu feedback, hidden categories) into a compact map
/// that AI providers can hand to Gemini *in addition to* the raw
/// lists. Without this layer every prompt re-derives "this user
/// likes drama" by looking at recent titles — and gets inconsistent
/// answers across rails.
///
/// Weighting scheme (per source row, summed into the aggregates):
///   * Explicit "more like this" feedback → +1.2 (strongest)
///   * Favourite                          → +1.0
///   * Finished episode/movie             → +0.8
///   * Watched 75-100%                    → +0.6
///   * Watched 25-75%                     → +0.3
///   * Watched <25%                       → -0.2  (opened, bailed)
///   * Hidden category                    → -1.0  (per-category)
///   * Explicit dislike feedback          → -1.5  (strongest neg)
///
/// Affinity maps are sorted descending by score; callers usually
/// take the top 5-10 entries when composing prompts.
class TasteProfile {
  /// Category label → weighted score. Keys are the catalogue's
  /// raw category names (e.g. "KOMEDi & ROMANTiK"). Higher = more
  /// preferred. Negative scores mean the user actively avoids the
  /// category (hidden in Settings or disliked items dominate it).
  final Map<String, double> categoryAffinity;

  /// Actor name → weighted score. Same scale as [categoryAffinity].
  /// Names are taken from `channel.cast`, top-billed first.
  final Map<String, double> actorAffinity;

  /// Director name → weighted score.
  final Map<String, double> directorAffinity;

  /// Categories the user has hidden in Settings → Categories. AI
  /// should not surface items from these.
  final Set<String> hiddenCategories;

  /// streamIds the user explicitly disliked via the ⋯ menu.
  final Set<int> dislikedIds;

  /// streamIds the user explicitly marked "more like this".
  final Set<int> moreLikeIds;

  /// Total weighted score of all positive signals — gives the AI
  /// a sense of how much signal it has. Profiles with <2.0 here
  /// are "cold start" and should lean on critical acclaim more
  /// than personal taste.
  final double signalStrength;

  const TasteProfile({
    this.categoryAffinity = const {},
    this.actorAffinity = const {},
    this.directorAffinity = const {},
    this.hiddenCategories = const {},
    this.dislikedIds = const {},
    this.moreLikeIds = const {},
    this.signalStrength = 0,
  });

  bool get isCold => signalStrength < 2.0;

  /// Top [limit] categories by score, descending. Negative scores
  /// excluded by default — those are "avoid", surfaced separately.
  List<MapEntry<String, double>> topCategories({int limit = 8}) {
    return categoryAffinity.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(limit).toList();
  }

  List<MapEntry<String, double>> topActors({int limit = 10}) {
    return actorAffinity.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(limit).toList();
  }

  List<MapEntry<String, double>> topDirectors({int limit = 8}) {
    return directorAffinity.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value))
      ..take(limit).toList();
  }

  /// Categories the user clearly steers away from — explicit
  /// hidden, OR aggregate score below -0.5.
  List<String> avoidedCategories({int limit = 6}) {
    final out = <String>{...hiddenCategories};
    final negatives = categoryAffinity.entries
        .where((e) => e.value <= -0.5)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in negatives) {
      if (out.length >= limit) break;
      out.add(e.key);
    }
    return out.take(limit).toList();
  }

  /// Compact prompt-friendly JSON the AI can read alongside the
  /// raw history/favorites lists. Lists are pre-truncated and
  /// the aggregates appear with their numeric scores so the AI
  /// can weigh them rather than treat each entry equally.
  Map<String, dynamic> toPromptJson() {
    Map<String, double> truncate(
            List<MapEntry<String, double>> entries) =>
        {
          for (final e in entries.take(8))
            e.key: double.parse(e.value.toStringAsFixed(2)),
        };
    return {
      'signalStrength': double.parse(signalStrength.toStringAsFixed(2)),
      'isColdStart': isCold,
      'topCategories': truncate(topCategories()),
      'topActors': truncate(topActors()),
      'topDirectors': truncate(topDirectors()),
      'avoidedCategories': avoidedCategories(),
    };
  }
}
