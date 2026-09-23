import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/m3u_lan_identity.dart';

void main() {
  final local = [
    const M3uIdentity(
      streamId: 42,
      type: 'live',
      sourceKey: 'tvg:a',
      sourceUrl: 'https://example.invalid/a',
      accountId: 1,
    ),
  ];
  final payload = <String, dynamic>{
    'm3uIdentities': [
      {'streamId': 999, 'type': 'live', 'sourceKey': 'tvg:a'},
    ],
    'favorites': [
      {'streamId': 999, 'streamType': 'live'},
    ],
    'progress': [
      {'streamId': 999, 'type': 'live'},
    ],
    'tombstones': [
      {'streamId': 999, 'streamType': 'live'},
    ],
    'enrichment': [
      {'streamId': 999, 'type': 'live'},
    ],
  };
  test(
    'different device IDs remap by full source key for all content rows',
    () {
      final result = remapM3uLanPayload(payload, local, requireAll: true);
      for (final key in ['favorites', 'progress', 'tombstones', 'enrichment']) {
        expect((result[key] as List).single['streamId'], 42);
        expect((payload[key] as List).single['streamId'], 999);
      }
    },
  );
  test(
    'unknown and old-peer IDs never attach to a coincidentally equal ID',
    () {
      final old = <String, dynamic>{
        'favorites': [
          {'streamId': 42, 'streamType': 'live'},
        ],
      };
      expect(remapM3uLanPayload(old, local)['favorites'], isEmpty);
      expect(
        () => remapM3uLanPayload(old, local, requireAll: true),
        throwsFormatException,
      );
    },
  );
}
