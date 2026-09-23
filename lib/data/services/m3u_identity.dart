import 'dart:isolate';
import '../datasources/local/database.dart';
import 'm3u_parser.dart';

/// A URL is exact (query parameters can select different content). A provider's
/// tvg-id is used only when it identifies one URL within this media type.
class PreparedM3uChannel {
  final M3UEntry entry;
  final String name;
  final M3uIdentity identity;
  const PreparedM3uChannel(this.entry, this.name, this.identity);
}

class PreparedM3u {
  final M3UParseResult summary;
  final List<PreparedM3uChannel> channels;
  const PreparedM3u(this.summary, this.channels);
}

Future<PreparedM3u> prepareM3uAsync(
  List<M3UEntry> entries,
  List<M3uIdentity> identities,
  List<Channel> previous, {
  Set<(String, int)> legacyReferences = const {},
}) => Isolate.run(
  () => prepareM3u(
    entries,
    identities,
    previous,
    legacyReferences: legacyReferences,
  ),
);

/// Hash is only a candidate. Persistent full-key comparisons resolve collisions.
/// 52 bits remain exact in JSON and above legacy 31-bit IDs.
int m3uIdCandidate(String key) {
  var a = 0x811c9dc5, b = 0x9e3779b9;
  for (final c in key.codeUnits) {
    a = ((a ^ c) * 0x01000193) & 0xffffffff;
    b = ((b ^ c) * 0x01000193) & 0xffffffff;
  }
  return ((b & 0xfffff) << 32) | a | 0x100000000;
}

PreparedM3u prepareM3u(
  List<M3UEntry> entries,
  List<M3uIdentity> identities,
  List<Channel> previous, {
  int Function(String) candidate = m3uIdCandidate,
  Set<(String, int)> legacyReferences = const {},
}) {
  final types = [
    for (final e in entries)
      classifyStreamType(
        url: e.url,
        name: e.name,
        tvgType: e.tvgType,
        groupTitle: e.groupTitle,
      ),
  ];
  final tvgUrls = <(String, String), Set<String>>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.tvgId?.isNotEmpty == true) {
      tvgUrls.putIfAbsent((types[i], e.tvgId!), () => {}).add(e.url);
    }
  }
  final byKey = {for (final r in identities) (r.type, r.sourceKey): r};
  final byUrl = <(String, String), M3uIdentity>{};
  final reserved = <(String, int)>{
    for (final r in identities) (r.type, r.streamId),
    for (final r in previous) (r.type, r.streamId),
  };
  for (final r in identities) {
    byUrl.putIfAbsent((r.type, r.sourceUrl), () => r);
  }
  final legacy = <(String, String), Channel>{};
  final registered = {for (final r in identities) (r.type, r.streamId)};
  for (final r in previous) {
    if (r.streamUrl != null && !registered.contains((r.type, r.streamId))) {
      legacy.putIfAbsent((r.type, r.streamUrl!), () => r);
    }
  }
  final keyed = <(String, String), M3UEntry>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i], type = types[i];
    final uniqueTvg =
        e.tvgId?.isNotEmpty == true && tvgUrls[(type, e.tvgId!)]!.length == 1;
    final key = uniqueTvg ? 'tvg:${e.tvgId}' : 'url:${e.url}';
    keyed.putIfAbsent((type, key), () => e);
  }
  final keys = keyed.keys.toList()
    ..sort((a, b) {
      final typeOrder = a.$1.compareTo(b.$1);
      return typeOrder != 0 ? typeOrder : a.$2.compareTo(b.$2);
    });
  // v1-v3 backups did not include a registry/catalogue. Recover references
  // only if exactly one current source has that legacy URL+name hash.
  final legacyCandidates = <(String, int), List<(String, String)>>{};
  for (final key in keys) {
    final e = keyed[key]!;
    final legacyId = stableM3uChannelId(
      url: e.url,
      name: e.name.isNotEmpty ? e.name : e.tvgName,
    );
    if (legacyReferences.contains((key.$1, legacyId))) {
      legacyCandidates.putIfAbsent((key.$1, legacyId), () => []).add(key);
    }
  }
  final recoverable = <(String, String), int>{
    for (final entry in legacyCandidates.entries)
      if (entry.value.length == 1 && !reserved.contains(entry.key))
        entry.value.single: entry.key.$2,
  };
  reserved.addAll(legacyReferences);
  final claimed = <(String, int)>{};
  // Reserve exact matches first, so a changed/ambiguous tvg-id cannot steal one.
  final assigned = <(String, String), int>{};
  for (final key in keys) {
    final old = byKey[key];
    if (old != null) {
      assigned[key] = old.streamId;
      claimed.add((key.$1, old.streamId));
    }
  }
  final channels = <PreparedM3uChannel>[];
  for (final key in keys) {
    final e = keyed[key]!;
    final type = key.$1;
    int? id = assigned[key];
    final urlMatch = byUrl[(type, e.url)];
    if (id == null &&
        urlMatch != null &&
        !claimed.contains((type, urlMatch.streamId))) {
      id = urlMatch.streamId;
    }
    id ??= legacy[(type, e.url)]?.streamId;
    id ??= recoverable[key];
    if (id == null || claimed.contains((type, id)) && assigned[key] != id) {
      id = candidate('$type\u0000${key.$2}') & 0x1fffffffffffff;
      while (reserved.contains((type, id))) {
        id = (id! + 1) & 0x1fffffffffffff;
      }
    }
    final resolvedId = id!;
    claimed.add((type, resolvedId));
    reserved.add((type, resolvedId));
    var name = e.name.isNotEmpty ? e.name : e.tvgName ?? '';
    if (name.isEmpty) {
      name = (Uri.tryParse(e.url)?.pathSegments.lastOrNull ?? '')
          .replaceAll(RegExp(r'\.\w{2,4}$'), '')
          .replaceAll(RegExp(r'[_-]'), ' ')
          .trim();
    }
    if (name.isEmpty) name = 'Kanal $id';
    channels.add(
      PreparedM3uChannel(
        e,
        name,
        M3uIdentity(
          streamId: resolvedId,
          type: type,
          sourceKey: key.$2,
          sourceUrl: e.url,
          accountId: 0,
        ),
      ),
    );
  }
  return PreparedM3u(
    buildParseResult(channels.map((c) => c.entry).toList()),
    channels,
  );
}
