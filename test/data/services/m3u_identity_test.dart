import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/m3u_identity.dart';
import 'package:lifeostv/data/services/m3u_parser.dart';

M3UEntry entry(int n, {String? name, String? tvg, String? url}) => M3UEntry(
  name: name ?? 'Channel $n',
  url: url ?? 'https://example.invalid/$n.ts',
  tvgId: tvg,
);

void main() {
  test('old backup references recover only unambiguous legacy hashes', () {
    final a = entry(1);
    final id = stableM3uChannelId(url: a.url, name: a.name);
    expect(
      prepareM3u(
        [a],
        [],
        [],
        legacyReferences: {('live', id)},
      ).channels.single.identity.streamId,
      id,
    );
    final ambiguous = prepareM3u(
      [entry(18310), entry(33232)],
      [],
      [],
      legacyReferences: {('live', 799436981)},
    );
    expect(
      ambiguous.channels.any((c) => c.identity.streamId == 799436981),
      isFalse,
    );
  });

  test('known legacy hash collision survives as two different identities', () {
    final a = entry(18310), b = entry(33232);
    expect(stableM3uChannelId(url: a.url, name: a.name), 799436981);
    expect(stableM3uChannelId(url: b.url, name: b.name), 799436981);
    final result = prepareM3u([a, b], [], []);
    expect(
      result.channels.map((r) => r.identity.streamId).toSet(),
      hasLength(2),
    );
  });
  test(
    'forced collision is resolved and durable across removal and reorder',
    () {
      final first = prepareM3u(
        [entry(2), entry(1)],
        [],
        [],
        candidate: (_) => 10,
      );
      expect(first.channels.map((c) => c.identity.streamId).toSet(), {10, 11});
      final saved = first.channels.map((c) => c.identity).toList();
      final next = prepareM3u(
        [entry(3), entry(2)],
        saved,
        [],
        candidate: (_) => 10,
      );
      expect(next.channels.first.identity.streamId, saved.last.streamId);
      expect(next.channels.last.identity.streamId, 12);
      final restored = prepareM3u([entry(1)], saved, [], candidate: (_) => 10);
      expect(restored.channels.single.identity.streamId, 10);
    },
  );
  test(
    'legacy ID retained by URL and unique tvg-id survives signed URL/name change',
    () {
      final old = Channel(
        streamId: 42,
        name: 'Old',
        type: 'live',
        categoryId: 'x',
        streamUrl: entry(1).url,
        accountId: 1,
      );
      final first = prepareM3u([entry(1, tvg: 'channel')], [], [old]);
      expect(first.channels.single.identity.streamId, 42);
      final next = prepareM3u(
        [
          entry(
            1,
            tvg: 'channel',
            name: 'New',
            url: 'https://example.invalid/1.ts?token=changed',
          ),
        ],
        [first.channels.single.identity],
        [],
      );
      expect(next.channels.single.identity.streamId, 42);
    },
  );
  test('duplicate tvg IDs retain distinct URLs and media types', () {
    final result = prepareM3u(
      [
        entry(1, tvg: 'shared'),
        entry(2, tvg: 'shared'),
        const M3UEntry(
          name: 'Film',
          url: 'https://example.invalid/1.mp4',
          tvgId: 'shared',
        ),
      ],
      [],
      [],
    );
    expect(result.channels, hasLength(3));
    expect(
      result.channels
          .where((c) => c.identity.type == 'live')
          .every((c) => c.identity.sourceKey.startsWith('url:')),
      isTrue,
    );
  });
  test(
    '100k entries have no loss and reorder/rename retains all IDs',
    () async {
      final entries = List.generate(100000, entry);
      final first = await prepareM3uAsync(entries, [], []);
      expect(first.channels, hasLength(100000));
      expect(
        first.channels.map((c) => c.identity.streamId).toSet(),
        hasLength(100000),
      );
      final ids = {
        for (final c in first.channels) c.entry.url: c.identity.streamId,
      };
      final second = await prepareM3uAsync(
        entries.reversed
            .map((e) => M3UEntry(name: 'Renamed ${e.name}', url: e.url))
            .toList(),
        first.channels.map((c) => c.identity).toList(),
        [],
      );
      expect({
        for (final c in second.channels) c.entry.url: c.identity.streamId,
      }, ids);
    },
  );
}
