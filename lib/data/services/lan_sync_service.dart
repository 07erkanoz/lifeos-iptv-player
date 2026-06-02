import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/settings_repository.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;

/// Same-network device-to-device sync — NO cloud, NO database server.
///
/// One device (the SENDER) opens an ephemeral HTTP server, advertises
/// itself over mDNS (`_lifeostv-sync._tcp`) and shows a 6-digit PIN.
/// The other device (the RECEIVER) discovers it over mDNS, the user
/// types the PIN, then the receiver pulls a JSON snapshot and applies
/// the categories the user picked (account, favourites, continue-
/// watching, settings, profiles).
///
/// Security model: the server only runs while the pairing screen is
/// open, every request must carry the matching PIN in the
/// `x-sync-pin` header, and traffic never leaves the LAN. Credentials
/// / API keys do travel as plain JSON over the local network — that's
/// the standard trade-off for PIN-gated local pairing; it's gated and
/// ephemeral, not exposed to the internet.

// ---------------------------------------------------------------------------
//  Sync categories — what the user can opt into transferring
// ---------------------------------------------------------------------------

enum SyncCategory { account, favorites, progress, settings, profiles }

extension SyncCategoryWire on SyncCategory {
  /// Stable wire key used in the `/export?cats=` query and payload map.
  String get wire => switch (this) {
        SyncCategory.account => 'accounts',
        SyncCategory.favorites => 'favorites',
        SyncCategory.progress => 'progress',
        SyncCategory.settings => 'settings',
        SyncCategory.profiles => 'profiles',
      };

  static SyncCategory? fromWire(String s) {
    for (final c in SyncCategory.values) {
      if (c.wire == s) return c;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
//  A discovered sender on the LAN
// ---------------------------------------------------------------------------

class SyncPeer {
  final String name; // friendly device name from mDNS attributes
  final String host;
  final int port;
  const SyncPeer({required this.name, required this.host, required this.port});

  String get baseUrl => 'http://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is SyncPeer && other.host == host && other.port == port;
  @override
  int get hashCode => Object.hash(host, port);
}

// ---------------------------------------------------------------------------
//  Manifest — counts only, no sensitive data. Lets the receiver render
//  the category checkboxes before pulling anything heavy / private.
// ---------------------------------------------------------------------------

class SyncManifest {
  final String device;
  final int accounts;
  final int profiles;
  final int favorites;
  final int progress;
  final bool hasSettings;

  const SyncManifest({
    required this.device,
    required this.accounts,
    required this.profiles,
    required this.favorites,
    required this.progress,
    required this.hasSettings,
  });

  factory SyncManifest.fromJson(Map<String, dynamic> j) => SyncManifest(
        device: (j['device'] ?? '') as String,
        accounts: (j['accounts'] ?? 0) as int,
        profiles: (j['profiles'] ?? 0) as int,
        favorites: (j['favorites'] ?? 0) as int,
        progress: (j['progress'] ?? 0) as int,
        hasSettings: (j['hasSettings'] ?? false) as bool,
      );

  int countFor(SyncCategory c) => switch (c) {
        SyncCategory.account => accounts,
        SyncCategory.profiles => profiles,
        SyncCategory.favorites => favorites,
        SyncCategory.progress => progress,
        SyncCategory.settings => hasSettings ? 1 : 0,
      };
}

/// Outcome of an import — how many rows of each kind were applied.
class SyncImportResult {
  final int accounts;
  final int profiles;
  final int favorites;
  final int progress;
  final bool settings;
  const SyncImportResult({
    this.accounts = 0,
    this.profiles = 0,
    this.favorites = 0,
    this.progress = 0,
    this.settings = false,
  });
}

// ---------------------------------------------------------------------------
//  Service
// ---------------------------------------------------------------------------

class LanSyncService {
  static const String _serviceType = '_lifeostv-sync._tcp';
  static const int _payloadVersion = 1;
  static const String _pinHeader = 'x-sync-pin';

  final AppDatabase _db;
  final SharedPreferences _prefs;

  LanSyncService(this._db, this._prefs);

  // ── Sender state ─────────────────────────────────────────────────────────
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  String? _pin;

  /// The PIN the receiver must enter (null when not broadcasting).
  String? get pin => _pin;

  /// True while this device is offering its data to peers.
  bool get isBroadcasting => _server != null;

  String get _deviceName {
    try {
      final h = Platform.localHostname.trim();
      if (h.isNotEmpty) return h;
    } catch (_) {}
    return 'LifeOS (${Platform.operatingSystem})';
  }

  /// Android 13+ gates mDNS register/browse behind NEARBY_WIFI_DEVICES.
  /// No-op elsewhere. Same request the cast/DLNA discovery uses.
  Future<void> _ensureNearbyPermission() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.nearbyWifiDevices.status;
      if (!status.isGranted) {
        await Permission.nearbyWifiDevices.request();
      }
    } catch (_) {}
  }

  /// Start the HTTP server + mDNS broadcast. Returns the PIN to show.
  Future<String> startSending() async {
    await stopSending(); // idempotent — never double-bind
    await _ensureNearbyPermission();

    // Random-ish 6-digit PIN without dart:math (banned in some
    // contexts here): derive from the current microsecond clock.
    final seed = DateTime.now().microsecondsSinceEpoch;
    final pin = (seed % 900000 + 100000).toString();
    _pin = pin;

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handleRequest, onError: (_) {});

    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'LifeOS-${_deviceName.replaceAll(RegExp(r"[^A-Za-z0-9]"), "")}',
          type: _serviceType,
          port: server.port,
          attributes: {'device': _deviceName},
        ),
      );
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } catch (e) {
      if (kDebugMode) debugPrint('[LanSync] broadcast failed: $e');
      // Even without mDNS the receiver can still connect by typed IP,
      // so we keep the server alive.
    }

    return pin;
  }

  Future<void> stopSending() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _pin = null;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    // CORS-free local server; reject anything without the right PIN.
    final givenPin = req.headers.value(_pinHeader);
    if (_pin == null || givenPin != _pin) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.json;
    try {
      final path = req.uri.path;
      if (path == '/manifest') {
        res.write(jsonEncode(await _buildManifestJson()));
      } else if (path == '/export') {
        final catsParam = req.uri.queryParameters['cats'] ?? '';
        final cats = catsParam
            .split(',')
            .map((s) => SyncCategoryWire.fromWire(s.trim()))
            .whereType<SyncCategory>()
            .toSet();
        res.write(jsonEncode(await _buildPayload(cats)));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      if (kDebugMode) debugPrint('[LanSync] request error: $e');
    }
    await res.close();
  }

  // ── Export (sender side) ───────────────────────────────────────────────

  Future<Map<String, dynamic>> _buildManifestJson() async {
    final accounts = await _db.select(_db.accounts).get();
    final profiles = await _db.select(_db.profiles).get();
    final favs = await _db.select(_db.favorites).get();
    final prog = await _db.select(_db.playbackProgress).get();
    return {
      'v': _payloadVersion,
      'device': _deviceName,
      'accounts': accounts.length,
      'profiles': profiles.length,
      'favorites': favs.length,
      'progress': prog.length,
      'hasSettings': true,
    };
  }

  Future<Map<String, dynamic>> _buildPayload(Set<SyncCategory> cats) async {
    final out = <String, dynamic>{
      'v': _payloadVersion,
      'device': _deviceName,
    };

    if (cats.contains(SyncCategory.account)) {
      final rows = await _db.select(_db.accounts).get();
      out['accounts'] = [
        for (final a in rows)
          {
            'name': a.name,
            'type': a.type,
            'url': a.url,
            'username': a.username,
            'password': a.password,
            'isActive': a.isActive,
          }
      ];
    }

    if (cats.contains(SyncCategory.profiles)) {
      final rows = await _db.select(_db.profiles).get();
      out['profiles'] = [
        for (final p in rows)
          {
            'oldId': p.id,
            'name': p.name,
            'avatarKey': p.avatarKey,
            'isKids': p.isKids,
            'pin': p.pin,
          }
      ];
    }

    if (cats.contains(SyncCategory.favorites)) {
      final rows = await _db.select(_db.favorites).get();
      out['favorites'] = [
        for (final f in rows)
          {
            'streamId': f.streamId,
            'streamType': f.streamType,
            'name': f.name,
            'thumbnail': f.thumbnail,
            'addedAt': f.addedAt.millisecondsSinceEpoch,
            'profileId': f.profileId,
          }
      ];
    }

    if (cats.contains(SyncCategory.progress)) {
      final rows = await _db.select(_db.playbackProgress).get();
      out['progress'] = [
        for (final p in rows)
          {
            'streamId': p.streamId,
            'type': p.type,
            'position': p.position,
            'duration': p.duration,
            'updatedAt': p.updatedAt.millisecondsSinceEpoch,
            'isFinished': p.isFinished,
            'profileId': p.profileId,
          }
      ];
    }

    if (cats.contains(SyncCategory.settings)) {
      out['settings'] = _exportSettings();
    }

    return out;
  }

  /// Serialise the device-portable subset of AppSettings. We DELIBERATELY
  /// drop `defaultAccountId` (account ids differ per device) and the
  /// transient last-played track hints.
  Map<String, dynamic> _exportSettings() {
    final s = SettingsRepository(_prefs).loadSettings();
    return {
      'themeMode': s.themeMode.index,
      'language': s.language.index,
      'hardwareAcceleration': s.hardwareAcceleration,
      'bufferDuration': s.bufferDuration,
      'streamQuality': s.streamQuality.index,
      'autoNextEpisode': s.autoNextEpisode,
      'epgPastDays': s.epgPastDays,
      'parentalControlEnabled': s.parentalControlEnabled,
      'parentalPin': s.parentalPin,
      'autoHideAdult': s.autoHideAdult,
      'continueWatchingEnabled': s.continueWatchingEnabled,
      'showSkipIntroButton': s.showSkipIntroButton,
      'introSkipDefaultSeconds': s.introSkipDefaultSeconds,
      'showTrailer': s.showTrailer,
      'opensubtitlesApiKey': s.opensubtitlesApiKey,
      'geminiApiKey': s.geminiApiKey,
      'subtitlePreferredLanguage': s.subtitlePreferredLanguage,
      'subtitleFontSize': s.subtitleFontSize,
      'subtitleColor': s.subtitleColor,
      'subtitleBold': s.subtitleBold,
      'subtitleBackgroundEnabled': s.subtitleBackgroundEnabled,
      'fullscreenMode': s.fullscreenMode,
      'heroTrailerOnMobile': s.heroTrailerOnMobile,
    };
  }

  // ── Receiver side: discovery + fetch + import ────────────────────────────

  /// Discover senders on the LAN for [timeout]. Re-emits the growing
  /// list so the picker can update live.
  Stream<List<SyncPeer>> discoverPeers({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final controller = StreamController<List<SyncPeer>>();
    final found = <SyncPeer>{};
    BonsoirDiscovery? discovery;
    Timer? stopTimer;

    Future<void> cleanup() async {
      stopTimer?.cancel();
      try {
        await discovery?.stop();
      } catch (_) {}
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () async {
      controller.add(const []);
      try {
        await _ensureNearbyPermission();
        discovery = BonsoirDiscovery(type: _serviceType);
        await discovery!.initialize();
        discovery!.eventStream?.listen((event) {
          switch (event) {
            case BonsoirDiscoveryServiceFoundEvent():
              event.service.resolve(discovery!.serviceResolver);
              break;
            case BonsoirDiscoveryServiceResolvedEvent():
              final svc = event.service;
              final host = svc.host;
              final port = svc.port;
              if (host == null || port == 0) break;
              final name = svc.attributes['device'] ?? svc.name;
              if (found.add(SyncPeer(name: name, host: host, port: port)) &&
                  !controller.isClosed) {
                controller.add(found.toList());
              }
              break;
            default:
              break;
          }
        });
        await discovery!.start();
        stopTimer = Timer(timeout, cleanup);
      } catch (e) {
        if (kDebugMode) debugPrint('[LanSync] discovery failed: $e');
        await cleanup();
      }
    };
    controller.onCancel = cleanup;
    return controller.stream;
  }

  /// Fetch the manifest from [peer], authenticating with [pin].
  /// Returns null on wrong PIN / unreachable host.
  Future<SyncManifest?> fetchManifest(SyncPeer peer, String pin) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {_pinHeader: pin},
        validateStatus: (s) => s != null && s < 500,
      ));
      final res = await dio.getUri<dynamic>(
        Uri.parse('${peer.baseUrl}/manifest'),
      );
      if (res.statusCode != 200) return null;
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      if (data is! Map) return null;
      return SyncManifest.fromJson(data.cast<String, dynamic>());
    } catch (e) {
      if (kDebugMode) debugPrint('[LanSync] fetchManifest failed: $e');
      return null;
    }
  }

  /// Pull the selected [cats] from [peer] and apply them locally.
  /// Returns a summary; throws on transport failure so the UI can
  /// surface a clear error.
  Future<SyncImportResult> pullAndApply({
    required SyncPeer peer,
    required String pin,
    required Set<SyncCategory> cats,
    required int activeProfileId,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
      headers: {_pinHeader: pin},
      validateStatus: (s) => s != null && s < 500,
    ));
    final catsParam = cats.map((c) => c.wire).join(',');
    final res = await dio.getUri<dynamic>(
      Uri.parse('${peer.baseUrl}/export?cats=$catsParam'),
    );
    if (res.statusCode != 200) {
      throw Exception('export status ${res.statusCode}');
    }
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    if (data is! Map) throw Exception('bad payload');
    return _applyPayload(
      data.cast<String, dynamic>(),
      cats: cats,
      activeProfileId: activeProfileId,
    );
  }

  Future<SyncImportResult> _applyPayload(
    Map<String, dynamic> payload, {
    required Set<SyncCategory> cats,
    required int activeProfileId,
  }) async {
    var accountsAdded = 0;
    var profilesAdded = 0;
    var favsAdded = 0;
    var progAdded = 0;
    var settingsApplied = false;

    // 1) Accounts — dedupe by (type, url, username). Insert account
    //    rows FIRST so favourites/progress streamIds line up once the
    //    target loads the same provider's playlist.
    if (cats.contains(SyncCategory.account) && payload['accounts'] is List) {
      final existing = await _db.select(_db.accounts).get();
      bool existsAlready(String type, String url, String? user) =>
          existing.any((a) =>
              a.type == type && a.url == url && a.username == user);
      final hadNoAccounts = existing.isEmpty;
      int? activateId;
      for (final raw in (payload['accounts'] as List)) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final type = (m['type'] ?? 'xtream') as String;
        final url = (m['url'] ?? '') as String;
        final user = m['username'] as String?;
        if (url.isEmpty) continue;
        if (existsAlready(type, url, user)) continue;
        final id = await _db.into(_db.accounts).insert(
              AccountsCompanion.insert(
                name: (m['name'] ?? url) as String,
                type: type,
                url: url,
                username: Value(user),
                password: Value(m['password'] as String?),
                isActive: const Value(false),
              ),
            );
        accountsAdded++;
        if ((m['isActive'] ?? false) == true) activateId = id;
      }
      // Only auto-activate the imported account when the target had no
      // accounts (the TV-onboarding case). Otherwise we don't yank the
      // user off whatever they were already watching.
      if (hadNoAccounts && activateId != null) {
        await _db.transaction(() async {
          await (_db.update(_db.accounts)
                ..where((t) => t.isActive.equals(true)))
              .write(const AccountsCompanion(isActive: Value(false)));
          await (_db.update(_db.accounts)
                ..where((t) => t.id.equals(activateId!)))
              .write(const AccountsCompanion(isActive: Value(true)));
        });
      }
    }

    // 2) Profiles — dedupe by name; build oldId → newId map. When the
    //    user did NOT opt to sync profiles, everything funnels into the
    //    target's active profile.
    final profileIdMap = <int, int>{};
    if (cats.contains(SyncCategory.profiles) && payload['profiles'] is List) {
      final existing = await _db.select(_db.profiles).get();
      for (final raw in (payload['profiles'] as List)) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final oldId = (m['oldId'] ?? 0) as int;
        final name = (m['name'] ?? '') as String;
        if (name.isEmpty) continue;
        final match = existing.where((p) => p.name == name).toList();
        if (match.isNotEmpty) {
          profileIdMap[oldId] = match.first.id;
          continue;
        }
        final newId = await _db.into(_db.profiles).insert(
              ProfilesCompanion.insert(
                name: name,
                avatarKey: Value((m['avatarKey'] ?? 'default') as String),
                isKids: Value((m['isKids'] ?? false) as bool),
                pin: Value(m['pin'] as String?),
              ),
            );
        profileIdMap[oldId] = newId;
        profilesAdded++;
      }
    }

    int mapProfile(int oldId) => profileIdMap[oldId] ?? activeProfileId;

    // 3) Favourites — remap profileId, upsert on the composite PK.
    if (cats.contains(SyncCategory.favorites) && payload['favorites'] is List) {
      await _db.batch((batch) {
        for (final raw in (payload['favorites'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          batch.insert(
            _db.favorites,
            FavoritesCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              streamType: (m['streamType'] ?? '') as String,
              name: (m['name'] ?? '') as String,
              thumbnail: Value(m['thumbnail'] as String?),
              addedAt: Value(DateTime.fromMillisecondsSinceEpoch(
                  (m['addedAt'] ?? 0) as int)),
              profileId: Value(mapProfile((m['profileId'] ?? 1) as int)),
            ),
            mode: InsertMode.insertOrReplace,
          );
          favsAdded++;
        }
      });
    }

    // 4) Continue-watching — same remap + upsert.
    if (cats.contains(SyncCategory.progress) && payload['progress'] is List) {
      await _db.batch((batch) {
        for (final raw in (payload['progress'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          batch.insert(
            _db.playbackProgress,
            PlaybackProgressCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              type: (m['type'] ?? 'movie') as String,
              position: (m['position'] ?? 0) as int,
              duration: (m['duration'] ?? 0) as int,
              updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(
                  (m['updatedAt'] ?? 0) as int)),
              isFinished: Value((m['isFinished'] ?? false) as bool),
              profileId: Value(mapProfile((m['profileId'] ?? 1) as int)),
            ),
            mode: InsertMode.insertOrReplace,
          );
          progAdded++;
        }
      });
    }

    // 5) Settings — overlay onto the current settings via copyWith so
    //    we never null-out fields the payload omitted, and never copy
    //    the device-specific defaultAccountId.
    if (cats.contains(SyncCategory.settings) && payload['settings'] is Map) {
      _applySettings((payload['settings'] as Map).cast<String, dynamic>());
      settingsApplied = true;
    }

    return SyncImportResult(
      accounts: accountsAdded,
      profiles: profilesAdded,
      favorites: favsAdded,
      progress: progAdded,
      settings: settingsApplied,
    );
  }

  void _applySettings(Map<String, dynamic> m) {
    final repo = SettingsRepository(_prefs);
    final cur = repo.loadSettings();
    T pick<T>(String k, T fallback) => (m[k] is T) ? m[k] as T : fallback;

    final next = cur.copyWith(
      themeMode: AppThemeMode
          .values[pick<int>('themeMode', cur.themeMode.index)
              .clamp(0, AppThemeMode.values.length - 1)],
      language: AppLanguage.values[pick<int>('language', cur.language.index)
          .clamp(0, AppLanguage.values.length - 1)],
      hardwareAcceleration:
          pick<bool>('hardwareAcceleration', cur.hardwareAcceleration),
      bufferDuration: pick<int>('bufferDuration', cur.bufferDuration),
      streamQuality: StreamQuality
          .values[pick<int>('streamQuality', cur.streamQuality.index)
              .clamp(0, StreamQuality.values.length - 1)],
      autoNextEpisode: pick<bool>('autoNextEpisode', cur.autoNextEpisode),
      epgPastDays: pick<int>('epgPastDays', cur.epgPastDays),
      parentalControlEnabled:
          pick<bool>('parentalControlEnabled', cur.parentalControlEnabled),
      parentalPin: m['parentalPin'] as String? ?? cur.parentalPin,
      autoHideAdult: pick<bool>('autoHideAdult', cur.autoHideAdult),
      continueWatchingEnabled:
          pick<bool>('continueWatchingEnabled', cur.continueWatchingEnabled),
      showSkipIntroButton:
          pick<bool>('showSkipIntroButton', cur.showSkipIntroButton),
      introSkipDefaultSeconds:
          pick<int>('introSkipDefaultSeconds', cur.introSkipDefaultSeconds),
      showTrailer: pick<bool>('showTrailer', cur.showTrailer),
      opensubtitlesApiKey:
          m['opensubtitlesApiKey'] as String? ?? cur.opensubtitlesApiKey,
      geminiApiKey: m['geminiApiKey'] as String? ?? cur.geminiApiKey,
      subtitlePreferredLanguage: pick<String>(
          'subtitlePreferredLanguage', cur.subtitlePreferredLanguage),
      subtitleFontSize: pick<int>('subtitleFontSize', cur.subtitleFontSize),
      subtitleColor: pick<String>('subtitleColor', cur.subtitleColor),
      subtitleBold: pick<bool>('subtitleBold', cur.subtitleBold),
      subtitleBackgroundEnabled:
          pick<bool>('subtitleBackgroundEnabled', cur.subtitleBackgroundEnabled),
      fullscreenMode: pick<bool>('fullscreenMode', cur.fullscreenMode),
      heroTrailerOnMobile:
          pick<bool>('heroTrailerOnMobile', cur.heroTrailerOnMobile),
    );
    // Fire-and-forget; saveSettings is async but the prefs write is
    // effectively synchronous for our purposes.
    unawaited(repo.saveSettings(next));
  }
}

/// Provider. `keepAlive` so the sender's HTTP server survives brief
/// widget rebuilds while the pairing screen is open.
final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  return LanSyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(sharedPreferencesProvider),
  );
});
