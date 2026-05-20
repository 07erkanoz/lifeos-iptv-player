/// One curated axis of similar content — a related-by-X bucket of
/// items the AI thinks the user would enjoy given what they're
/// looking at.
///
/// Example shapes Gemini might return:
///   * axis "Aynı yönetmenden", subtitle "Hong Sung-chang"
///     → director's other library items
///   * axis "Aynı oyuncularla", subtitle "Yoo Yeon-seok ana rolde"
///     → cast overlap
///   * axis "Benzer atmosfer", subtitle null
///     → mood / tone match across genres
///   * axis "Aynı dönem ve ülke", subtitle "2020+ Kore polisiyesi"
///     → narrower contextual cluster
///
/// We don't hard-code the set of axes — Gemini picks whatever makes
/// sense for the input item, in the user's language. That keeps the
/// UI flexible: a Korean drama detail might surface "Same lead
/// actor" prominently; a western might surface "Same director"
/// instead.
class SimilarGroup {
  /// Bucket title in the user's language, e.g. "Aynı yönetmenden".
  /// Required. Empty string is treated as malformed.
  final String axisLabel;

  /// Optional short context for the axis ("Hong Sung-chang",
  /// "Yoo Yeon-seok ana rolde"). Rendered in lighter text under
  /// the axis label.
  final String? axisSubtitle;

  /// The picks for this axis, ordered by Gemini's preference.
  /// Empty list = empty bucket; caller filters those out before
  /// rendering.
  final List<SimilarItem> items;

  const SimilarGroup({
    required this.axisLabel,
    this.axisSubtitle,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;

  static SimilarGroup? fromJson(Map<String, dynamic> json) {
    final label = json['axisLabel']?.toString().trim();
    if (label == null || label.isEmpty) return null;
    final subtitleRaw = json['axisSubtitle']?.toString().trim();
    final subtitle =
        (subtitleRaw != null && subtitleRaw.isNotEmpty) ? subtitleRaw : null;
    final rawItems = json['items'];
    final parsed = <SimilarItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map<String, dynamic>) {
          final item = SimilarItem.fromJson(raw);
          if (item != null) parsed.add(item);
        }
      }
    }
    if (parsed.isEmpty) return null;
    return SimilarGroup(
      axisLabel: label,
      axisSubtitle: subtitle,
      items: parsed,
    );
  }
}

/// A single AI pick inside a [SimilarGroup]. References a real
/// library item by [streamId]; the UI looks the channel up before
/// rendering, and silently drops anything the model hallucinated.
class SimilarItem {
  /// Matches `Channel.streamId` in the local DB.
  final int streamId;

  /// One- or two-sentence justification specific to *this* axis.
  /// Not the same as a generic plot — it's why **this item** fits
  /// **this bucket** ("Aynı yönetmenin 2024 yapımı, benzer kara
  /// mizah").
  final String reason;

  const SimilarItem({required this.streamId, required this.reason});

  static SimilarItem? fromJson(Map<String, dynamic> json) {
    final raw = json['streamId'];
    int? sid;
    if (raw is int) {
      sid = raw;
    } else if (raw is num) {
      sid = raw.toInt();
    } else if (raw != null) {
      sid = int.tryParse(raw.toString());
    }
    if (sid == null || sid <= 0) return null;
    final reason = json['reason']?.toString().trim() ?? '';
    if (reason.isEmpty) return null;
    return SimilarItem(streamId: sid, reason: reason);
  }
}
