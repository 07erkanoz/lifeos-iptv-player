import 'lan_pairing_gate.dart';
import 'm3u_lan_identity.dart';
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

import 'package:lifeostv/core/platform_helper.dart';
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

enum SyncCategory {
  account,
  favorites,
  progress,
  settings,
  profiles,
  enrichment,
}

extension SyncCategoryWire on SyncCategory {
  /// Stable wire key used in the `/export?cats=` query and payload map.
  String get wire => switch (this) {
    SyncCategory.account => 'accounts',
    SyncCategory.favorites => 'favorites',
    SyncCategory.progress => 'progress',
    SyncCategory.settings => 'settings',
    SyncCategory.profiles => 'profiles',
    SyncCategory.enrichment => 'enrichment',
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
  final String deviceId; // stable id from mDNS `id` attribute ('' if absent)
  const SyncPeer({
    required this.name,
    required this.host,
    required this.port,
    this.deviceId = '',
  });

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
  final int enrichment;

  const SyncManifest({
    required this.device,
    required this.accounts,
    required this.profiles,
    required this.favorites,
    required this.progress,
    required this.hasSettings,
    this.enrichment = 0,
  });

  factory SyncManifest.fromJson(Map<String, dynamic> j) => SyncManifest(
    device: (j['device'] ?? '') as String,
    accounts: (j['accounts'] ?? 0) as int,
    profiles: (j['profiles'] ?? 0) as int,
    favorites: (j['favorites'] ?? 0) as int,
    progress: (j['progress'] ?? 0) as int,
    hasSettings: (j['hasSettings'] ?? false) as bool,
    enrichment: (j['enrichment'] ?? 0) as int,
  );

  int countFor(SyncCategory c) => switch (c) {
    SyncCategory.account => accounts,
    SyncCategory.profiles => profiles,
    SyncCategory.favorites => favorites,
    SyncCategory.progress => progress,
    SyncCategory.settings => hasSettings ? 1 : 0,
    SyncCategory.enrichment => enrichment,
  };
}

/// A device this one has paired with before (PIN entered once). The
/// shared [token] replaces the PIN for silent auto-sync; [deviceId]
/// matches the `id` attribute the peer advertises over mDNS.
class TrustedPeer {
  final String token;
  final String deviceId;
  final String name;
  const TrustedPeer({
    required this.token,
    required this.deviceId,
    required this.name,
  });

  Map<String, dynamic> toJson() => {
    'token': token,
    'deviceId': deviceId,
    'name': name,
  };
  factory TrustedPeer.fromJson(Map<String, dynamic> j) => TrustedPeer(
    token: (j['token'] ?? '') as String,
    deviceId: (j['deviceId'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}

/// Outcome of an import — how many rows of each kind were applied.
class SyncImportResult {
  final int accounts;
  final int profiles;
  final int favorites;
  final int progress;
  final bool settings;
  final int enrichment;
  const SyncImportResult({
    this.accounts = 0,
    this.profiles = 0,
    this.favorites = 0,
    this.progress = 0,
    this.settings = false,
    this.enrichment = 0,
  });
}

// ---------------------------------------------------------------------------
//  Service
// ---------------------------------------------------------------------------

class LanSyncService {
  static const String _serviceType = '_lifeostv-sync._tcp';
  static const int _payloadVersion = 1;
  static const String _pinHeader = 'x-sync-pin';
  static const String _tokenHeader = 'x-sync-token';
  static const String _kDeviceId = 'lan_sync_device_id';
  static const String _kTrusted = 'lan_sync_trusted_peers';

  final AppDatabase _db;
  final SharedPreferences _prefs;

  LanSyncService(this._db, this._prefs);

  // ── Server state ─────────────────────────────────────────────────────────
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  final _pairing = LanPairingGate();
  bool _autoWanted = false; // keep server up for token-only auto-sync

  /// The PIN the receiver must enter (null when not broadcasting).
  String? get pin => _pairing.pin;

  /// True while this device is offering its data to peers.
  bool get isBroadcasting => _server != null;

  /// Stable per-install id, advertised over mDNS so trusted peers can
  /// recognise this device across sessions / IP changes.
  String get deviceId {
    var id = _prefs.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = _randomId();
      _prefs.setString(_kDeviceId, id);
    }
    return id;
  }

  List<TrustedPeer> get trustedPeers {
    final raw = _prefs.getString(_kTrusted);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map) TrustedPeer.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  bool get hasTrustedPeers => trustedPeers.isNotEmpty;

  void _saveTrusted(List<TrustedPeer> peers) {
    _prefs.setString(
      _kTrusted,
      jsonEncode([for (final p in peers) p.toJson()]),
    );
  }

  /// Add / refresh a trusted peer (dedupe by deviceId).
  void addTrustedPeer(TrustedPeer peer) {
    final list = trustedPeers.where((p) => p.deviceId != peer.deviceId).toList()
      ..add(peer);
    _saveTrusted(list);
  }

  void removeTrustedPeer(String deviceId) {
    _saveTrusted(trustedPeers.where((p) => p.deviceId != deviceId).toList());
  }

  TrustedPeer? _trustedByToken(String token) {
    for (final p in trustedPeers) {
      if (p.token == token) return p;
    }
    return null;
  }

  static String _randomId() => LanPairingGate.newToken();

  static const String _kDeviceName = 'lan_sync_device_name';

  /// Friendly, stable device label shown in peer pickers. Android's
  /// `Platform.localHostname` is usually "localhost", so we derive a
  /// readable per-platform default instead and cache it (the user can
  /// override it later via [setDeviceName]).
  String get _deviceName {
    final stored = _prefs.getString(_kDeviceName)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return _defaultDeviceName();
  }

  void setDeviceName(String name) {
    _prefs.setString(_kDeviceName, name.trim());
  }

  String _defaultDeviceName() {
    if (Platform.isAndroid) {
      return PlatformHelper.isTV ? 'Android TV' : 'Android';
    }
    if (Platform.isIOS) return 'iPhone / iPad';
    if (Platform.isLinux) {
      try {
        final h = Platform.localHostname.trim();
        if (h.isNotEmpty && h != 'localhost') return 'Linux ($h)';
      } catch (_) {}
      return 'Linux';
    }
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    return 'LifeOS';
  }

  /// Active profile id (SharedPreferences, default 1). Used as the
  /// fallback target when an incoming row's profile name doesn't exist
  /// locally so favourites never silently vanish.
  int get _activeProfileId => _prefs.getInt('active_profile_id') ?? 1;

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

  /// Bring up the HTTP server + mDNS broadcast if they aren't already.
  /// Used by both manual pairing and the always-on auto-sync server.
  Future<void> _ensureServerAndBroadcast() async {
    if (_server != null) return;
    await _ensureNearbyPermission();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handleRequest, onError: (_) {});
    try {
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'LifeOS-${_deviceName.replaceAll(RegExp(r"[^A-Za-z0-9]"), "")}',
          type: _serviceType,
          port: server.port,
          attributes: {'device': _deviceName, 'id': deviceId},
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
  }

  Future<void> _teardownServer() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }

  /// Start the HTTP server + mDNS broadcast for MANUAL pairing.
  /// Returns the PIN to show.
  Future<String> startSending() async {
    final pin = _pairing.start();
    try {
      await _ensureServerAndBroadcast();
      return pin;
    } catch (_) {
      _pairing.stop();
      rethrow;
    }
  }

  /// Leave the manual pairing screen. Keeps the server alive in
  /// token-only auto mode when auto-sync is on, otherwise tears down.
  Future<void> stopSending() async {
    _pairing.stop();
    if (!_autoWanted) await _teardownServer();
  }

  /// Keep a token-gated server up so trusted peers can push/pull while
  /// the app is open. Called at startup when auto-sync is enabled.
  Future<void> startAutoServer() async {
    _autoWanted = true;
    await _ensureServerAndBroadcast();
  }

  Future<void> stopAutoServer() async {
    _autoWanted = false;
    if (_pairing.pin == null) await _teardownServer();
  }

  /// A request is authorised if it carries the active pairing PIN OR a
  /// token belonging to an already-trusted peer.
  bool _authorised(HttpRequest req) {
    final givenPin = req.headers.value(_pinHeader);
    if (_pairing.verify(givenPin)) return true;
    final token = req.headers.value(_tokenHeader);
    if (token != null && token.isNotEmpty && _trustedByToken(token) != null) {
      return true;
    }
    return false;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    if (!_authorised(req)) {
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
      } else if (path == '/trust' && req.method == 'POST') {
        // The receiver establishes mutual trust: it sends a shared
        // token + its own id/name; we store it and hand back ours so
        // it can store us too.
        final body = await utf8.decoder.bind(req).join();
        final m = (jsonDecode(body) as Map).cast<String, dynamic>();
        final token = (m['token'] ?? '') as String;
        final peerId = (m['deviceId'] ?? '') as String;
        final peerName = (m['name'] ?? '') as String;
        if (token.isNotEmpty && peerId.isNotEmpty) {
          addTrustedPeer(
            TrustedPeer(token: token, deviceId: peerId, name: peerName),
          );
          // Make pairing symmetric: this (sender) side should now also
          // keep its server up and auto-sync on future launches.
          _autoWanted = true;
          _prefs.setBool('auto_sync_enabled', true);
          if (kDebugMode) {
            debugPrint('[LanSync] trusted peer added: $peerName ($peerId)');
          }
        }
        res.write(jsonEncode({'deviceId': deviceId, 'name': _deviceName}));
      } else if (path == '/sync' && req.method == 'POST') {
        // Two-way merge: ingest the caller's rows, then return ours so
        // both sides converge in a single round trip.
        final body = await utf8.decoder.bind(req).join();
        final incoming = (jsonDecode(body) as Map).cast<String, dynamic>();
        await _mergeIncoming(incoming);
        res.write(jsonEncode(await _buildSyncSnapshot()));
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
    final enrich = await _db.select(_db.contentEnrichment).get();
    return {
      'v': _payloadVersion,
      'device': _deviceName,
      'contentAccountKey': await _contentAccountKey(),
      'accounts': accounts.length,
      'profiles': profiles.length,
      'favorites': favs.length,
      'progress': prog.length,
      'hasSettings': true,
      'enrichment': enrich.length,
    };
  }

  /// Stable per-account keys ("type|url|username") for the active
  /// accounts. Enrichment is keyed by raw streamId, which only lines
  /// up across devices that share the same Xtream/M3U provider — so we
  /// only apply received enrichment when the two devices have at least
  /// one account in common.
  Future<Set<String>> _accountKeys() async {
    final rows = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(_db.accountScope ?? 0))).get();
    return {for (final a in rows) '${a.type}|${a.url}|${a.username ?? ""}'};
  }

  String _contentIdentity(Account account) => jsonEncode([
    account.type,
    account.url.replaceAll(RegExp(r'/+$'), ''),
    account.username ?? '',
  ]);

  Future<String?> _contentAccountKey() async {
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(_db.accountScope ?? 0))).getSingleOrNull();
    return account == null ? null : _contentIdentity(account);
  }

  List<Map<String, dynamic>> _enrichmentToJson(
    List<ContentEnrichmentData> rows,
  ) {
    return [
      for (final e in rows)
        {
          'streamId': e.streamId,
          'type': e.type,
          'genres': e.genres,
          'year': e.year,
          'mood': e.moodTags,
          'themes': e.themes,
          'warnings': e.contentWarnings,
          'age': e.ageRating,
          'confidence': e.confidence,
          'source': e.source,
        },
    ];
  }

  /// Apply received enrichment rows (insert-or-replace). Returns count.
  Future<int> _applyEnrichmentRows(List<dynamic> rows) async {
    var n = 0;
    await _db.accountBatch((batch) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final sid = (m['streamId'] as num?)?.toInt();
        final type = m['type'] as String?;
        if (sid == null || type == null) continue;
        batch.insert(
          _db.contentEnrichment,
          ContentEnrichmentCompanion.insert(
            streamId: sid,
            type: type,
            genres: Value(m['genres'] as String?),
            year: Value((m['year'] as num?)?.toInt()),
            moodTags: Value(m['mood'] as String?),
            themes: Value(m['themes'] as String?),
            contentWarnings: Value(m['warnings'] as String?),
            ageRating: Value(m['age'] as String?),
            confidence: Value((m['confidence'] as num?)?.toDouble()),
            source: Value(m['source'] as String?),
            updatedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
        n++;
      }
    });
    return n;
  }

  Future<Map<String, dynamic>> _withM3uIdentities(
    Map<String, dynamic> payload,
  ) async {
    final referenced = <(String, int)>{};
    for (final key in ['favorites', 'progress', 'tombstones', 'enrichment']) {
      final rows = payload[key];
      if (rows is! List) continue;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final type = raw['streamType'] ?? raw['type'], id = raw['streamId'];
        if (type is String && id is int) referenced.add((type, id));
      }
    }
    final ids = referenced.map((r) => r.$2).toSet().toList();
    final identities = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 500) {
      final rows = await (_db.select(
        _db.m3uIdentities,
      )..where((t) => t.streamId.isIn(ids.skip(i).take(500)))).get();
      for (final row in rows) {
        if (referenced.contains((row.type, row.streamId))) {
          identities.add({
            'streamId': row.streamId,
            'type': row.type,
            'sourceKey': row.sourceKey,
          });
        }
      }
    }
    return {...payload, 'm3uIdentities': identities};
  }

  Future<Map<String, dynamic>> _buildPayload(Set<SyncCategory> cats) async {
    final out = <String, dynamic>{
      'v': _payloadVersion,
      'device': _deviceName,
      'contentAccountKey': await _contentAccountKey(),
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
          },
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
          },
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
          },
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
          },
      ];
    }

    if (cats.contains(SyncCategory.settings)) {
      out['settings'] = _exportSettings();
    }

    if (cats.contains(SyncCategory.enrichment)) {
      final rows = await _db.select(_db.contentEnrichment).get();
      out['enrichment'] = _enrichmentToJson(rows);
      // Account fingerprints so the receiver can refuse mismatched
      // catalogues (enrichment is keyed by raw streamId).
      out['accountKeys'] = (await _accountKeys()).toList();
    }

    return _withM3uIdentities(out);
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
              final id = svc.attributes['id'] ?? '';
              // Never list ourselves — our own broadcast resolves too.
              if (id.isNotEmpty && id == deviceId) break;
              final name = svc.attributes['device'] ?? svc.name;
              if (found.add(
                    SyncPeer(name: name, host: host, port: port, deviceId: id),
                  ) &&
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
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {_pinHeader: pin},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
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
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 30),
        headers: {_pinHeader: pin},
        validateStatus: (s) => s != null && s < 500,
      ),
    );
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
    var enrichApplied = 0;

    // 1) Accounts — dedupe by (type, url, username). Insert account
    //    rows FIRST so favourites/progress streamIds line up once the
    //    target loads the same provider's playlist.
    if (cats.contains(SyncCategory.account) && payload['accounts'] is List) {
      final existing = await _db.select(_db.accounts).get();
      bool existsAlready(String type, String url, String? user) => existing.any(
        (a) => a.type == type && a.url == url && a.username == user,
      );
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
        final id = await _db
            .into(_db.accounts)
            .insert(
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

    final sourceKey = payload['contentAccountKey'];
    final matchingAccounts = await _db.select(_db.accounts).get();
    final targetAccount = matchingAccounts
        .where((a) => _contentIdentity(a) == sourceKey)
        .firstOrNull;
    final contentDb = targetAccount == null
        ? null
        : _db.forAccount(targetAccount.id);
    if (contentDb == null &&
        (cats.contains(SyncCategory.favorites) ||
            cats.contains(SyncCategory.progress) ||
            cats.contains(SyncCategory.enrichment))) {
      throw const FormatException(
        'Content account does not match a saved account',
      );
    }

    if (targetAccount?.type == 'm3u') {
      payload = remapM3uLanPayload(
        payload,
        await contentDb!.select(contentDb.m3uIdentities).get(),
        requireAll: true,
      );
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
        final newId = await _db
            .into(_db.profiles)
            .insert(
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
      await contentDb!.accountBatch((batch) {
        for (final raw in (payload['favorites'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          batch.insert(
            contentDb.favorites,
            FavoritesCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              streamType: (m['streamType'] ?? '') as String,
              name: (m['name'] ?? '') as String,
              thumbnail: Value(m['thumbnail'] as String?),
              addedAt: Value(
                DateTime.fromMillisecondsSinceEpoch((m['addedAt'] ?? 0) as int),
              ),
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
      await contentDb!.accountBatch((batch) {
        for (final raw in (payload['progress'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          batch.insert(
            contentDb.playbackProgress,
            PlaybackProgressCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              type: (m['type'] ?? 'movie') as String,
              position: (m['position'] ?? 0) as int,
              duration: (m['duration'] ?? 0) as int,
              updatedAt: Value(
                DateTime.fromMillisecondsSinceEpoch(
                  (m['updatedAt'] ?? 0) as int,
                ),
              ),
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

    if (cats.contains(SyncCategory.enrichment) &&
        payload['enrichment'] is List &&
        contentDb != null) {
      enrichApplied = await LanSyncService(
        contentDb,
        _prefs,
      )._applyEnrichmentRows(payload['enrichment'] as List);
    }

    return SyncImportResult(
      accounts: accountsAdded,
      profiles: profilesAdded,
      favorites: favsAdded,
      progress: progAdded,
      settings: settingsApplied,
      enrichment: enrichApplied,
    );
  }

  void _applySettings(Map<String, dynamic> m) {
    final repo = SettingsRepository(_prefs);
    final cur = repo.loadSettings();
    T pick<T>(String k, T fallback) => (m[k] is T) ? m[k] as T : fallback;

    final next = cur.copyWith(
      themeMode:
          AppThemeMode.values[pick<int>(
            'themeMode',
            cur.themeMode.index,
          ).clamp(0, AppThemeMode.values.length - 1)],
      language:
          AppLanguage.values[pick<int>(
            'language',
            cur.language.index,
          ).clamp(0, AppLanguage.values.length - 1)],
      hardwareAcceleration: pick<bool>(
        'hardwareAcceleration',
        cur.hardwareAcceleration,
      ),
      bufferDuration: pick<int>('bufferDuration', cur.bufferDuration),
      streamQuality:
          StreamQuality.values[pick<int>(
            'streamQuality',
            cur.streamQuality.index,
          ).clamp(0, StreamQuality.values.length - 1)],
      autoNextEpisode: pick<bool>('autoNextEpisode', cur.autoNextEpisode),
      epgPastDays: pick<int>('epgPastDays', cur.epgPastDays),
      parentalControlEnabled: pick<bool>(
        'parentalControlEnabled',
        cur.parentalControlEnabled,
      ),
      parentalPin: m['parentalPin'] as String? ?? cur.parentalPin,
      autoHideAdult: pick<bool>('autoHideAdult', cur.autoHideAdult),
      continueWatchingEnabled: pick<bool>(
        'continueWatchingEnabled',
        cur.continueWatchingEnabled,
      ),
      showSkipIntroButton: pick<bool>(
        'showSkipIntroButton',
        cur.showSkipIntroButton,
      ),
      introSkipDefaultSeconds: pick<int>(
        'introSkipDefaultSeconds',
        cur.introSkipDefaultSeconds,
      ),
      showTrailer: pick<bool>('showTrailer', cur.showTrailer),
      opensubtitlesApiKey:
          m['opensubtitlesApiKey'] as String? ?? cur.opensubtitlesApiKey,
      geminiApiKey: m['geminiApiKey'] as String? ?? cur.geminiApiKey,
      subtitlePreferredLanguage: pick<String>(
        'subtitlePreferredLanguage',
        cur.subtitlePreferredLanguage,
      ),
      subtitleFontSize: pick<int>('subtitleFontSize', cur.subtitleFontSize),
      subtitleColor: pick<String>('subtitleColor', cur.subtitleColor),
      subtitleBold: pick<bool>('subtitleBold', cur.subtitleBold),
      subtitleBackgroundEnabled: pick<bool>(
        'subtitleBackgroundEnabled',
        cur.subtitleBackgroundEnabled,
      ),
      fullscreenMode: pick<bool>('fullscreenMode', cur.fullscreenMode),
      heroTrailerOnMobile: pick<bool>(
        'heroTrailerOnMobile',
        cur.heroTrailerOnMobile,
      ),
    );
    // Fire-and-forget; saveSettings is async but the prefs write is
    // effectively synchronous for our purposes.
    unawaited(repo.saveSettings(next));
  }

  // ── Trust + auto-sync (favourites + continue-watching) ───────────────────

  /// Receiver side: after a manual transfer the user can opt to keep
  /// the devices paired. We mint a shared token, POST it to the sender
  /// (PIN-gated `/trust`), store the sender as trusted, and the sender
  /// stores us. Future syncs use the token — no PIN re-entry.
  Future<bool> establishTrust(SyncPeer peer, String pin) async {
    try {
      final token = _randomId();
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {_pinHeader: pin},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final res = await dio.postUri<dynamic>(
        Uri.parse('${peer.baseUrl}/trust'),
        data: jsonEncode({
          'token': token,
          'deviceId': deviceId,
          'name': _deviceName,
        }),
      );
      if (res.statusCode != 200) return false;
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      if (data is! Map) return false;
      final m = data.cast<String, dynamic>();
      addTrustedPeer(
        TrustedPeer(
          token: token,
          deviceId: (m['deviceId'] ?? peer.deviceId) as String,
          name: (m['name'] ?? peer.name) as String,
        ),
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[LanSync] establishTrust failed: $e');
      return false;
    }
  }

  /// Snapshot of favourites + continue-watching, keyed by profile NAME
  /// (ids differ across devices). Used by the two-way `/sync` merge.
  Future<Map<String, dynamic>> _buildSyncSnapshot() async {
    final profiles = await _db.select(_db.profiles).get();
    final idToName = {for (final p in profiles) p.id: p.name};
    final favs = await _db.select(_db.favorites).get();
    final prog = await _db.select(_db.playbackProgress).get();
    final enrich = await _db.select(_db.contentEnrichment).get();
    final tombstones = await _db.select(_db.syncTombstones).get();
    final catPrefs = await _db.select(_db.categoryPrefs).get();
    final geminiKey = SettingsRepository(_prefs).loadSettings().geminiApiKey;
    return _withM3uIdentities({
      'v': _payloadVersion,
      'contentAccountKey': await _contentAccountKey(),
      // Delete tombstones so a removal propagates instead of the peer
      // re-adding the favourite on the next additive merge.
      'tombstones': [
        for (final t in tombstones)
          {
            'entity': t.entity,
            'profileName': idToName[t.profileId] ?? '',
            'streamId': t.streamId,
            'streamType': t.streamType,
            'deletedAt': t.deletedAt.millisecondsSinceEpoch,
          },
      ],
      // Category-visibility prefs (hidden categories) — account-gated
      // on the receiver since categoryId only aligns within the same
      // provider. LWW by updatedAt.
      'categoryPrefs': [
        for (final c in catPrefs)
          {
            'categoryId': c.categoryId,
            'type': c.type,
            'isHidden': c.isHidden,
            'updatedAt': c.updatedAt.millisecondsSinceEpoch,
          },
      ],
      // Account fingerprints so the peer only applies our enrichment
      // when it shares the same provider (streamIds line up).
      'accountKeys': (await _accountKeys()).toList(),
      'enrichment': _enrichmentToJson(enrich),
      // Gemini key travels so paired devices can both enrich / use AI
      // without re-entering it. Adopted only if the peer has none.
      if (geminiKey != null && geminiKey.isNotEmpty) 'geminiApiKey': geminiKey,
      'favorites': [
        for (final f in favs)
          {
            'profileName': idToName[f.profileId] ?? '',
            'streamId': f.streamId,
            'streamType': f.streamType,
            'name': f.name,
            'thumbnail': f.thumbnail,
            'addedAt': f.addedAt.millisecondsSinceEpoch,
          },
      ],
      'progress': [
        for (final p in prog)
          {
            'profileName': idToName[p.profileId] ?? '',
            'streamId': p.streamId,
            'type': p.type,
            'position': p.position,
            'duration': p.duration,
            'updatedAt': p.updatedAt.millisecondsSinceEpoch,
            'isFinished': p.isFinished,
          },
      ],
    });
  }

  /// Merge a peer's snapshot into our DB. Favourites are additive (a
  /// row missing locally is inserted — we don't propagate deletes in
  /// v1). Continue-watching is last-write-wins on `updatedAt`. Rows
  /// for a profile name that doesn't exist locally are skipped (we
  /// never auto-create profiles here).
  Future<void> _mergeIncoming(Map<String, dynamic> snap) async {
    final identity = await _contentAccountKey();
    if (identity == null || snap['contentAccountKey'] != identity) return;
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(_db.accountScope ?? 0))).getSingleOrNull();
    if (account?.type == 'm3u') {
      snap = remapM3uLanPayload(
        snap,
        await _db.select(_db.m3uIdentities).get(),
      );
    }

    final profiles = await _db.select(_db.profiles).get();
    final nameToId = <String, int>{for (final p in profiles) p.name: p.id};
    // Unknown profile name → fall back to the active profile so a
    // single-profile user's favourites always land somewhere visible.
    int resolveProfile(String? name) =>
        (name != null ? nameToId[name] : null) ?? _activeProfileId;
    var favAdded = 0;
    var progAdded = 0;

    // ── Tombstones first ──────────────────────────────────────────
    // Merge incoming delete tombstones (taking the newest deletedAt
    // per key), then drop any local favourite the tombstone outdates.
    // Doing this BEFORE the additive favourites merge means a deletion
    // that's newer than the peer's copy wins; a re-add that's newer
    // than the deletion survives (handled in the favourites loop via
    // `tombAt`).
    final tombAt = <String, int>{}; // 'pid|type|streamId' -> deletedAt ms
    {
      final localTombs = await _db.select(_db.syncTombstones).get();
      for (final t in localTombs) {
        tombAt['${t.profileId}|${t.streamType}|${t.streamId}'] =
            t.deletedAt.millisecondsSinceEpoch;
      }
      if (snap['tombstones'] is List) {
        for (final raw in (snap['tombstones'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          if ((m['entity'] ?? 'favorite') != 'favorite') continue;
          final pid = resolveProfile(m['profileName'] as String?);
          final sid = (m['streamId'] ?? 0) as int;
          final stype = (m['streamType'] ?? '') as String;
          final ts = (m['deletedAt'] ?? 0) as int;
          final key = '$pid|$stype|$sid';
          if ((tombAt[key] ?? 0) >= ts) continue; // local tombstone newer
          tombAt[key] = ts;
          await _db
              .into(_db.syncTombstones)
              .insertOnConflictUpdate(
                SyncTombstonesCompanion.insert(
                  entity: 'favorite',
                  streamId: sid,
                  streamType: stype,
                  profileId: Value(pid),
                  deletedAt: Value(DateTime.fromMillisecondsSinceEpoch(ts)),
                ),
              );
        }
      }
      // Delete local favourites older than their tombstone.
      final localFavs = await _db.select(_db.favorites).get();
      for (final f in localFavs) {
        final key = '${f.profileId}|${f.streamType}|${f.streamId}';
        final dAt = tombAt[key];
        if (dAt != null && f.addedAt.millisecondsSinceEpoch <= dAt) {
          await (_db.delete(_db.favorites)
                ..where((t) => t.streamId.equals(f.streamId))
                ..where((t) => t.streamType.equals(f.streamType))
                ..where((t) => t.profileId.equals(f.profileId)))
              .go();
        }
      }
    }

    if (snap['favorites'] is List) {
      final existing = await _db.select(_db.favorites).get();
      final have = <String>{
        for (final f in existing)
          '${f.profileId}|${f.streamType}|${f.streamId}',
      };
      await _db.accountBatch((batch) {
        for (final raw in (snap['favorites'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          final pid = resolveProfile(m['profileName'] as String?);
          final key = '$pid|${m['streamType']}|${m['streamId']}';
          if (have.contains(key)) continue;
          final addedAt = (m['addedAt'] ?? 0) as int;
          // Skip the re-add when a tombstone is as-new-or-newer than
          // this add (the deletion wins).
          final dAt = tombAt[key];
          if (dAt != null && dAt >= addedAt) continue;
          batch.insert(
            _db.favorites,
            FavoritesCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              streamType: (m['streamType'] ?? '') as String,
              name: (m['name'] ?? '') as String,
              thumbnail: Value(m['thumbnail'] as String?),
              addedAt: Value(DateTime.fromMillisecondsSinceEpoch(addedAt)),
              profileId: Value(pid),
            ),
            mode: InsertMode.insertOrIgnore,
          );
          favAdded++;
        }
      });
    }

    if (snap['progress'] is List) {
      final existing = await _db.select(_db.playbackProgress).get();
      final localUpdated = <String, int>{
        for (final p in existing)
          '${p.profileId}|${p.type}|${p.streamId}':
              p.updatedAt.millisecondsSinceEpoch,
      };
      await _db.accountBatch((batch) {
        for (final raw in (snap['progress'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          final pid = resolveProfile(m['profileName'] as String?);
          final ts = (m['updatedAt'] ?? 0) as int;
          final key = '$pid|${m['type']}|${m['streamId']}';
          final localTs = localUpdated[key];
          // Only overwrite when the incoming row is strictly newer.
          if (localTs != null && localTs >= ts) continue;
          batch.insert(
            _db.playbackProgress,
            PlaybackProgressCompanion.insert(
              streamId: (m['streamId'] ?? 0) as int,
              type: (m['type'] ?? 'movie') as String,
              position: (m['position'] ?? 0) as int,
              duration: (m['duration'] ?? 0) as int,
              updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(ts)),
              isFinished: Value((m['isFinished'] ?? false) as bool),
              profileId: Value(pid),
            ),
            mode: InsertMode.insertOrReplace,
          );
          progAdded++;
        }
      });
    }

    // Enrichment — additive, gated on a shared account (same provider
    // → matching streamIds). This is what stops the second device from
    // re-paying Gemini to tag a catalogue the first already tagged.
    var enrichAdded = 0;
    if (snap['enrichment'] is List) {
      final srcKeys = (snap['accountKeys'] is List)
          ? (snap['accountKeys'] as List).whereType<String>().toSet()
          : <String>{};
      final mine = await _accountKeys();
      if (srcKeys.isEmpty || srcKeys.intersection(mine).isNotEmpty) {
        enrichAdded = await _applyEnrichmentRows(snap['enrichment'] as List);
      }
    }
    // Category-visibility prefs — LWW by updatedAt, then apply onto
    // the live categories table. Account-gated (categoryId aligns only
    // within the same provider) like enrichment.
    var catApplied = 0;
    if (snap['categoryPrefs'] is List) {
      final srcKeys = (snap['accountKeys'] is List)
          ? (snap['accountKeys'] as List).whereType<String>().toSet()
          : <String>{};
      final mine = await _accountKeys();
      if (srcKeys.isEmpty || srcKeys.intersection(mine).isNotEmpty) {
        final localPrefs = await _db.select(_db.categoryPrefs).get();
        final localAt = <String, int>{
          for (final p in localPrefs)
            '${p.categoryId}|${p.type}': p.updatedAt.millisecondsSinceEpoch,
        };
        for (final raw in (snap['categoryPrefs'] as List)) {
          if (raw is! Map) continue;
          final m = raw.cast<String, dynamic>();
          final cid = (m['categoryId'] ?? '') as String;
          final type = (m['type'] ?? '') as String;
          if (cid.isEmpty || type.isEmpty) continue;
          final ts = (m['updatedAt'] ?? 0) as int;
          final hidden = (m['isHidden'] ?? false) as bool;
          if ((localAt['$cid|$type'] ?? 0) >= ts) continue; // local newer
          await _db
              .into(_db.categoryPrefs)
              .insertOnConflictUpdate(
                CategoryPrefsCompanion.insert(
                  categoryId: cid,
                  type: type,
                  isHidden: Value(hidden),
                  updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(ts)),
                ),
              );
          await (_db.update(_db.categories)
                ..where((t) => t.id.equals(cid))
                ..where((t) => t.type.equals(type)))
              .write(CategoriesCompanion(isHidden: Value(hidden)));
          catApplied++;
        }
      }
    }

    // Gemini key — adopt only when we don't already have one, so a
    // device without AI configured inherits it from a paired device.
    final incomingKey = snap['geminiApiKey'] as String?;
    if (incomingKey != null && incomingKey.trim().isNotEmpty) {
      final repo = SettingsRepository(_prefs);
      final cur = repo.loadSettings();
      if (cur.geminiApiKey == null || cur.geminiApiKey!.trim().isEmpty) {
        unawaited(repo.saveSettings(cur.copyWith(geminiApiKey: incomingKey)));
        if (kDebugMode) debugPrint('[LanSync] adopted Gemini key from peer');
      }
    }
    if (kDebugMode) {
      debugPrint(
        '[LanSync] merged: favAdded=$favAdded progAdded=$progAdded '
        'enrichAdded=$enrichAdded catApplied=$catApplied',
      );
    }
  }

  /// Active pass: discover trusted peers on the LAN and run a two-way
  /// `/sync` with each. Safe to call on app start / resume. Returns the
  /// number of peers successfully synced.
  Future<int> runAutoSyncPass({
    Duration discovery = const Duration(seconds: 5),
  }) async {
    final trusted = trustedPeers;
    if (trusted.isEmpty) return 0;
    final byId = {for (final t in trusted) t.deviceId: t};

    // Collect discovered peers over the window.
    final peers = <SyncPeer>[];
    final sub = discoverPeers(timeout: discovery).listen((list) {
      peers
        ..clear()
        ..addAll(list);
    });
    await Future<void>.delayed(discovery + const Duration(milliseconds: 300));
    await sub.cancel();

    var synced = 0;
    final seen = <String>{};
    for (final peer in peers) {
      final t = byId[peer.deviceId];
      if (t == null) continue;
      if (!seen.add(peer.deviceId)) continue;
      if (await _syncWithPeer(peer, t.token)) synced++;
    }
    return synced;
  }

  Future<bool> _syncWithPeer(SyncPeer peer, String token) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 30),
          headers: {_tokenHeader: token},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final mine = await _buildSyncSnapshot();
      final res = await dio.postUri<dynamic>(
        Uri.parse('${peer.baseUrl}/sync'),
        data: jsonEncode(mine),
      );
      if (res.statusCode != 200) return false;
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      if (data is! Map) return false;
      await _mergeIncoming(data.cast<String, dynamic>());
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[LanSync] syncWithPeer failed: $e');
      return false;
    }
  }
}

/// Provider. `keepAlive` so the sender's HTTP server survives brief
/// widget rebuilds while the pairing screen is open.
final lanSyncServiceProvider = Provider<LanSyncService>((ref) {
  final service = LanSyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(() {
    service.stopSending();
    service.stopAutoServer();
  });
  return service;
});
