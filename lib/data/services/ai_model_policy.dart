/// Feature → Gemini model routing.
///
/// Tek `gemini-2.5-flash`'in her şeye uygulanması hem maliyetli hem
/// kalite-suboptimal: kısa JSON parse işleri Flash-Lite ile %60 daha
/// ucuz, uzun analiz/diyalog işleri daha güçlü modelden hatırı sayılır
/// kalite kazanır. Bu policy class'ı feature başına model seçimini
/// merkezîleştirir; modelleri burada değiştirip tüm AI surface'i tek
/// yerden tune edebiliriz.
///
/// Modelleri sabit string olarak tutuyoruz çünkü Google'ın model
/// stringleri stabil (versiyon farkı = yeni string). Geçişte sadece
/// burayı güncellemek yeterli.
class AiModelPolicy {
  /// Search intent parse + auto-suggest chips — kısa JSON, düşük
  /// latency önemli. Flash-Lite hem yarı maliyet hem 2-3x hızlı.
  static const String parser = 'gemini-2.5-flash-lite';

  /// Search rerank (curateLibraryByQuery) — biraz daha karmaşık
  /// reasoning ama hâlâ bounded list seçimi.
  static const String searchRerank = 'gemini-2.5-flash';

  /// Dashboard rail picks (recommendForYou, recommendForMood,
  /// generateHeroBillboard, weeklyDigest) — orta karmaşıklıkta
  /// reasoning, taste signals'a göre seçim.
  static const String dashboardRanking = 'gemini-2.5-flash';

  /// Plot enrichment (translate, summarize, fillIn, detailedInfo),
  /// cast career summary, series recap — uzun prose üretimi, kalite
  /// > maliyet. Flash de yeterli ama future-proof için config'lendi.
  static const String longText = 'gemini-2.5-flash';

  /// Tonight chat assistant — multi-turn diyalog, taste discussion,
  /// film analysis. En karmaşık conversational use case.
  static const String chat = 'gemini-2.5-flash';

  /// Embeddings — semantic retrieval index için. Henüz aktif değil
  /// ama config'i hazır.
  static const String embedding = 'gemini-embedding-001';

  /// Greeting banner — tek 1-2 cümle, en ucuz model uygun.
  static const String greeting = 'gemini-2.5-flash-lite';

  /// Episode recap summaries — toplu batch çağrı, ucuz model.
  static const String episodeSummary = 'gemini-2.5-flash-lite';
}
