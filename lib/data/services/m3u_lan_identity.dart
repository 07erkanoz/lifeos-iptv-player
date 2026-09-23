import '../datasources/local/database.dart';

/// Provider account identity alone is insufficient for M3U: legacy IDs and
/// locally resolved hash collisions may differ. Only full source keys match.
Map<String, dynamic> remapM3uLanPayload(
  Map<String, dynamic> payload,
  List<M3uIdentity> local, {
  bool requireAll = false,
}) {
  final byKey = {for (final r in local) (r.type, r.sourceKey): r.streamId};
  final remote = <(String, int), int>{};
  final identities = payload['m3uIdentities'];
  if (identities is List) {
    for (final raw in identities) {
      if (raw is! Map || raw['type'] is! String || raw['streamId'] is! int) {
        continue;
      }
      final id = byKey[(raw['type'] as String, raw['sourceKey'])];
      if (id != null) {
        remote[(raw['type'] as String, raw['streamId'] as int)] = id;
      }
    }
  }
  final out = Map<String, dynamic>.of(payload);
  for (final key in ['favorites', 'progress', 'tombstones', 'enrichment']) {
    final rows = payload[key];
    if (rows is! List) continue;
    final mapped = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final type = raw['streamType'] ?? raw['type'];
      final id = type is String && raw['streamId'] is int
          ? remote[(type, raw['streamId'] as int)]
          : null;
      if (id == null) {
        if (requireAll) {
          throw const FormatException(
            'M3U kimlikleri eşleşmiyor. İki cihazda da listeyi güncelleyin.',
          );
        }
        continue;
      }
      mapped.add({...Map<String, dynamic>.from(raw), 'streamId': id});
    }
    out[key] = mapped;
  }
  return out;
}
