/// Keywords that indicate adult/NSFW content in category or channel names.
const adultKeywords = [
  'adult',
  'xxx',
  '+18',
  '18+',
  'porn',
  'erotic',
  'sex',
  'yetiskin',
  'yetişkin',
  'erotik',
  'نساء', // Arabic: women (often used in adult IPTV)
  'للكبار', // Arabic: for adults
];

/// Check if a name contains adult/NSFW keywords (case-insensitive).
bool isAdultContent(String name) {
  final lower = name.toLowerCase();
  return adultKeywords.any((keyword) => lower.contains(keyword));
}

/// Filter a list of items, removing those with adult content names.
List<T> filterAdultContent<T>(
  List<T> items,
  String Function(T) getName,
) {
  return items.where((item) => !isAdultContent(getName(item))).toList();
}
