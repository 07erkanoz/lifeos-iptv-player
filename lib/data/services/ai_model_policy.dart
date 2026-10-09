/// All text features use the selected production model. Embeddings have an
/// independent endpoint and index contract; they are never routed to Flash.
class AiModelPolicy {
  static const textModel = 'gemini-3.8-flash';
  static const parser = textModel;
  static const searchRerank = textModel;
  static const dashboardRanking = textModel;
  static const longText = textModel;
  static const chat = textModel;
  static const greeting = textModel;
  static const episodeSummary = textModel;
  static const catalogEnrichment = textModel;
  static const embedding = 'gemini-embedding-001';
}
