/// One AI-picked title in a "what should I watch?" response.
///
/// Gemini returns the [streamId] of an item from the library sample
/// it was given, plus a free-text [reason] explaining why it's a fit
/// for the user's question. The UI looks the [streamId] up in the
/// channels table to render a real poster + metadata card; the
/// model itself is intentionally tiny and printable.
class TonightRecommendation {
  /// References `Channel.streamId` in the local DB. If Gemini hands
  /// back an id we don't recognise (hallucinated, or the item was
  /// removed mid-call), the UI silently drops the recommendation
  /// rather than showing a broken card.
  final int streamId;

  /// One- or two-sentence justification in the user's language.
  /// Rendered under the title on the card. Already trimmed.
  final String reason;

  const TonightRecommendation({
    required this.streamId,
    required this.reason,
  });

  /// Coerce a `{streamId, reason}` map. Tolerates stringified ints
  /// (Gemini sometimes emits them despite the schema). Returns null
  /// if either field can't be recovered — caller filters nulls out
  /// of the list.
  static TonightRecommendation? fromJson(Map<String, dynamic> json) {
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
    return TonightRecommendation(streamId: sid, reason: reason);
  }
}

/// Top-level result returned by `GeminiService.recommendForTonight`.
///
/// Two halves: a free-text [message] (a one-liner intro / framing
/// the picks, in the user's language) and a [recommendations] list
/// of concrete titles. Either half may be empty; callers should
/// fall back gracefully (e.g. show the message even if no
/// recommendations matched library items).
class TonightResponse {
  /// Conversational text from the AI ("İşte 3 öneri:" / "Daha
  /// fazla bilgi verir misin?"). Rendered as a chat bubble.
  final String message;

  /// Ordered list — Gemini's preference, best-fit first.
  final List<TonightRecommendation> recommendations;

  const TonightResponse({
    required this.message,
    required this.recommendations,
  });

  bool get isEmpty => message.isEmpty && recommendations.isEmpty;

  factory TonightResponse.fromJson(Map<String, dynamic> json) {
    final msg = json['message']?.toString().trim() ?? '';
    final raw = json['recommendations'];
    final list = <TonightRecommendation>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final r = TonightRecommendation.fromJson(item);
          if (r != null) list.add(r);
        }
      }
    }
    return TonightResponse(message: msg, recommendations: list);
  }
}

/// One side of a chat exchange. Kept session-only (not persisted) —
/// when the user reopens the chat sheet, history resets.
class ChatMessage {
  final bool fromUser;
  final String text;

  /// Set on AI messages that come with a recommendation list, so the
  /// chat bubble renders the cards inline.
  final List<TonightRecommendation> recommendations;

  const ChatMessage({
    required this.fromUser,
    required this.text,
    this.recommendations = const [],
  });
}
