import 'dart:convert';

import 'package:lifeostv/data/datasources/local/database.dart';

/// Validates the entire portable document before any persistent data is touched.
/// Version 4 includes durable M3U identities; v3 added owning account IDs.
/// Versions 1/2 are upgraded using their active legacy catalogue owner.
/// This also preserves account-keyed EPG preferences without lossy remapping.
class BackupDocument {
  static const magic = 'lifeos-tv-backup';
  static const version = 4;

  final Map<String, List<Map<String, dynamic>>> tables;
  final Map<String, dynamic> settings;

  BackupDocument._(this.tables, this.settings);

  static bool isDeviceSetting(String key) =>
      key.startsWith('lan_sync_') ||
      key == 'auto_sync_enabled' ||
      key == 'gemini_api_key' ||
      key == 'opensubtitles_api_key';

  static bool isCacheSetting(String key) =>
      key.startsWith('xmltv_cache_') ||
      key.startsWith('xmltv_ts_') ||
      key.startsWith('sync_meta_') ||
      key.startsWith('acct_info_') ||
      key.startsWith('ai_rail_cache:') ||
      key.startsWith('personalized_picks_snapshot_') ||
      key.startsWith('last_epg_sync_timestamp');

  static bool isPortableSetting(String key) =>
      !isDeviceSetting(key) && !isCacheSetting(key);

  static void validateSettings(Map<String, dynamic> settings) {
    for (final entry in settings.entries) {
      final value = entry.value;
      if (value is! bool &&
          value is! int &&
          value is! String &&
          !(value is double && value.isFinite) &&
          !(value is List && value.every((e) => e is String))) {
        throw FormatException('Invalid preference type: ${entry.key}');
      }
    }
  }

  factory BackupDocument.parse(String source) {
    try {
      final payload = jsonDecode(source) as Map<String, dynamic>;
      if (payload['magic'] != magic) {
        throw const FormatException('Not a LifeOs TV backup file');
      }
      final v = payload['version'];
      if (v is! int || v < 1 || v > version) {
        throw const FormatException('Unsupported backup version');
      }
      final legacy = v == 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      var legacyOwner = 0;
      final result = <String, List<Map<String, dynamic>>>{};

      void read<T>(
        String key,
        T Function(Map<String, dynamic>) decode,
        List<String> primaryKey, {
        Map<String, dynamic> defaults = const {},
      }) {
        var raw = payload[key];
        if (key == 'm3uIdentities' && v < 4 && raw == null) raw = <dynamic>[];
        if (legacy &&
            raw == null &&
            !{
              'accounts',
              'favorites',
              'playbackProgress',
              'seriesTracking',
            }.contains(key)) {
          raw = <dynamic>[];
        }
        if (raw is! List) throw FormatException('Missing backup table: $key');
        final seen = <String>{};
        result[key] = [
          for (final item in raw)
            () {
              final row = <String, dynamic>{
                if (legacy) ...defaults,
                ...Map<String, dynamic>.from(item as Map),
              };
              final scoped = key != 'accounts' && key != 'profiles';
              if (scoped && v < 3) row['accountId'] = legacyOwner;
              if (scoped && row['accountId'] is! int) {
                throw FormatException('Missing account identity in $key');
              }
              for (final field in [
                'createdAt',
                'addedAt',
                'updatedAt',
                'lastCheckedAt',
                'lastUsedAt',
                'deletedAt',
              ]) {
                if (row[field] is String) {
                  final date = DateTime.tryParse(row[field] as String);
                  if (date == null) {
                    throw FormatException('Invalid date in $key');
                  }
                  row[field] = date.millisecondsSinceEpoch;
                }
              }
              decode(
                row,
              ); // Generated typed row decoder checks all required fields.
              final identity = jsonEncode([
                if (scoped) row['accountId'],
                for (final field in primaryKey) row[field],
              ]);
              if (!seen.add(identity)) {
                throw FormatException('Duplicate row in $key');
              }
              return row;
            }(),
        ];
      }

      read(
        'accounts',
        Account.fromJson,
        ['id'],
        defaults: {
          'name': 'Unnamed',
          'type': 'xtream',
          'url': '',
          'isActive': false,
          'createdAt': now,
        },
      );
      final oldAccounts = result['accounts']!;
      final oldActive = oldAccounts.where((r) => r['isActive'] == true).toList()
        ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      legacyOwner = oldActive.isNotEmpty
          ? oldActive.first['id'] as int
          : oldAccounts.length == 1
          ? oldAccounts.single['id'] as int
          : 0;
      read('profiles', Profile.fromJson, ['id']);
      if (legacy) {
        result['profiles'] = [
          {
            'id': 1,
            'name': 'Varsayılan',
            'avatarKey': 'default',
            'isKids': false,
            'pin': null,
            'createdAt': now,
          },
        ];
      }
      read(
        'favorites',
        Favorite.fromJson,
        ['streamId', 'streamType', 'profileId'],
        defaults: {'name': '', 'addedAt': now, 'profileId': 1},
      );
      read(
        'watchlist',
        WatchlistData.fromJson,
        ['streamId', 'streamType', 'profileId'],
        defaults: {'name': '', 'addedAt': now, 'profileId': 1},
      );
      read(
        'playbackProgress',
        PlaybackProgressData.fromJson,
        ['streamId', 'type', 'profileId'],
        defaults: {
          'position': 0,
          'duration': 0,
          'isFinished': false,
          'updatedAt': now,
          'profileId': 1,
        },
      );
      read(
        'seriesTracking',
        SeriesTrackingData.fromJson,
        ['seriesId', 'profileId'],
        defaults: {
          'knownEpisodeCount': 0,
          'newEpisodeCount': 0,
          'hasNewEpisodes': false,
          'lastCheckedAt': now,
          'profileId': 1,
        },
      );
      read('introMarkers', IntroMarker.fromJson, ['seriesId']);
      read('aiFeedback', AiFeedbackData.fromJson, [
        'streamId',
        'type',
        'action',
        'profileId',
      ]);
      read('searchHistory', SearchHistoryData.fromJson, ['query', 'profileId']);
      read('categoryPrefs', CategoryPref.fromJson, ['categoryId', 'type']);
      read('syncTombstones', SyncTombstone.fromJson, [
        'entity',
        'streamId',
        'streamType',
        'profileId',
      ]);

      read('m3uIdentities', M3uIdentity.fromJson, ['streamId', 'type']);
      final sourceKeys = <String>{};
      for (final row in result['m3uIdentities']!) {
        if ((row['streamId'] as int) < 0 ||
            (row['streamId'] as int) > 0x1fffffffffffff ||
            !{'live', 'movie', 'series'}.contains(row['type']) ||
            (row['sourceKey'] as String).isEmpty ||
            (row['sourceUrl'] as String).isEmpty ||
            !sourceKeys.add(
              jsonEncode([row['accountId'], row['type'], row['sourceKey']]),
            )) {
          throw const FormatException('Invalid M3U identity');
        }
      }

      final accounts = result['accounts']!;
      final profiles = result['profiles']!;
      final accountIds = accounts.map((r) => r['id'] as int).toSet();
      final profileIds = profiles.map((r) => r['id'] as int).toSet();
      if (accountIds.any((id) => id <= 0) ||
          profileIds.any((id) => id <= 0) ||
          !profileIds.contains(1)) {
        throw const FormatException('Invalid account/profile identity');
      }
      if (accounts.any((r) => !{'xtream', 'm3u'}.contains(r['type']))) {
        throw const FormatException('Invalid account type');
      }
      for (final entry in result.entries) {
        for (final row in entry.value) {
          if (row.containsKey('accountId') &&
              row['accountId'] != 0 &&
              !accountIds.contains(row['accountId'])) {
            throw FormatException('Unknown account in ${entry.key}');
          }
          if (row.containsKey('profileId') &&
              !profileIds.contains(row['profileId'])) {
            throw FormatException('Unknown profile in ${entry.key}');
          }
          for (final field in [
            'position',
            'duration',
            'knownEpisodeCount',
            'newEpisodeCount',
            'introStartMs',
            'introEndMs',
            'useCount',
          ]) {
            final value = row[field];
            if (value != null && (value is! int || value < 0)) {
              throw FormatException('Invalid $field in ${entry.key}');
            }
          }
          if (row.containsKey('introStartMs') &&
              (row['introEndMs'] as int) < (row['introStartMs'] as int)) {
            throw const FormatException('Invalid intro interval');
          }
        }
      }

      final rawSettings = payload['settings'];
      if (rawSettings is! Map<String, dynamic>) {
        throw const FormatException('Missing backup settings');
      }
      validateSettings(rawSettings);
      final settings = Map<String, dynamic>.fromEntries(
        rawSettings.entries.where((e) => isPortableSetting(e.key)),
      );
      for (final key in ['default_account_id', 'active_profile_id']) {
        if (settings.containsKey(key) && settings[key] is! int) {
          throw FormatException('Invalid preference: $key');
        }
      }
      // A single active DB row is authoritative. Repair legacy multiple-active
      // backups deterministically, preferring their saved selection.
      final active = accounts.where((r) => r['isActive'] == true).toList();
      final preferred = settings['default_account_id'];
      final int? activeId;
      if (active.length == 1) {
        activeId = active.single['id'] as int;
      } else if (accountIds.contains(preferred)) {
        activeId = preferred as int;
      } else if (active.isNotEmpty) {
        activeId = active
            .map((r) => r['id'] as int)
            .reduce((a, b) => a > b ? a : b);
      } else {
        activeId = accounts.isEmpty ? null : accounts.first['id'] as int;
      }
      for (final account in accounts) {
        account['isActive'] = account['id'] == activeId;
      }
      settings.remove('default_account_id');
      if (activeId != null) settings['default_account_id'] = activeId;
      if (!profileIds.contains(settings['active_profile_id'])) {
        settings['active_profile_id'] = 1;
      }
      settings.removeWhere(
        (key, _) =>
            key.startsWith('epg_url_') &&
            !accountIds.contains(
              int.tryParse(key.substring('epg_url_'.length)),
            ),
      );
      return BackupDocument._(result, settings);
    } on FormatException {
      rethrow;
    } catch (_) {
      // Never include the payload/credential values in an error message.
      throw const FormatException('Invalid backup row or field type');
    }
  }
}
