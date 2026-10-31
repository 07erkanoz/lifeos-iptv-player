import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Same-network device-to-device transfer screen.
///
/// Two roles, picked on entry:
///   * SEND    — this device opens an HTTP server, announces itself over
///               UDP + mDNS and shows a PIN and its IP address. Nothing
///               leaves until a peer authenticates.
///   * RECEIVE — discover senders (or type a sender's IP address), type
///               their PIN, choose which data categories to pull, then
///               apply.
class DeviceSyncScreen extends ConsumerStatefulWidget {
  /// Start directly in RECEIVE mode (used from first-run onboarding,
  /// where the only sensible action is to pull data into the fresh
  /// device).
  final bool startInReceive;

  /// Called from the "done" button after a successful import. When
  /// null we just pop. Onboarding passes a callback that routes to
  /// the dashboard instead of back to the welcome screen.
  final VoidCallback? onFinished;

  const DeviceSyncScreen({
    super.key,
    this.startInReceive = false,
    this.onFinished,
  });

  @override
  ConsumerState<DeviceSyncScreen> createState() => _DeviceSyncScreenState();
}

enum _Mode { chooser, sending, receiving }

class _DeviceSyncScreenState extends ConsumerState<DeviceSyncScreen> {
  late _Mode _mode = widget.startInReceive ? _Mode.receiving : _Mode.chooser;

  // Sending
  String? _pin;
  bool _startingServer = false;
  List<String> _localIps = const [];

  // Receiving
  /// One discovery run per visit to the device list. Created lazily so a
  /// rebuild (keyboard, focus, theme) does not restart the search; reset
  /// to null whenever the list should search again.
  Stream<List<SyncPeer>>? _peerStream;
  SyncPeer? _selectedPeer;
  SyncManifest? _manifest;
  final _pinController = TextEditingController();
  final Set<SyncCategory> _selected = {};
  bool _connecting = false;
  bool _importing = false;
  String? _error;
  SyncImportResult? _result;
  bool _remember = true; // "keep these devices in sync" on the select screen

  late final LanSyncService _svc;

  @override
  void initState() {
    super.initState();
    _svc = ref.read(lanSyncServiceProvider);
  }

  bool _syncingNow = false;

  void _forgetPeer(TrustedPeer p) {
    _svc.removeTrustedPeer(p.deviceId);
    // No peers left → auto-sync has nothing to do; turn it off and
    // drop the background server so it doesn't keep broadcasting.
    if (!_svc.hasTrustedPeers) {
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            ref.read(settingsProvider).copyWith(autoSyncEnabled: false),
          );
      _svc.stopAutoServer();
    }
    setState(() {});
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncingNow = true);
    await _svc.startAutoServer();
    final n = await _svc.runAutoSyncPass();
    if (!mounted) return;
    ref.read(settingsProvider.notifier).reload();
    ref.invalidate(activeProfileIdProvider);
    setState(() => _syncingNow = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n > 0 ? l10n.deviceSyncResult(n) : l10n.deviceSyncResultNone,
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Always tear the server + broadcast down when leaving.
    _svc.stopSending();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _enterSendMode() async {
    setState(() {
      _mode = _Mode.sending;
      _startingServer = true;
    });
    try {
      final pin = await _svc.startSending();
      final ips = await _svc.localAddresses();
      if (!mounted || _mode != _Mode.sending) {
        await _svc.stopSending();
        return;
      }
      setState(() {
        _pin = pin;
        _localIps = ips;
        _startingServer = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mode = _Mode.chooser;
        _startingServer = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.error)),
      );
    }
  }

  Future<void> _leaveSendMode() async {
    await _svc.stopSending();
    if (!mounted) return;
    setState(() {
      _mode = _Mode.chooser;
      _pin = null;
    });
  }

  void _resetReceive() {
    setState(() {
      _mode = _Mode.chooser;
      _peerStream = null;
      _selectedPeer = null;
      _manifest = null;
      _pinController.clear();
      _selected.clear();
      _connecting = false;
      _importing = false;
      _error = null;
      _result = null;
    });
  }

  Future<void> _connectToPeer() async {
    final peer = _selectedPeer;
    if (peer == null) return;
    final pin = _pinController.text.trim();
    if (pin.length < 4) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    var currentPeer = peer;
    SyncManifest? manifest;
    var unavailable = false;
    try {
      manifest = await _svc.fetchManifest(currentPeer, pin);
    } on LanSyncPeerUnavailable {
      unavailable = true;
      final refreshed = await _svc.rediscoverPeer(peer);
      if (refreshed != null) {
        currentPeer = refreshed;
        try {
          manifest = await _svc.fetchManifest(currentPeer, pin);
          unavailable = false;
        } on LanSyncPeerUnavailable {
          // Surface a connection error with the refreshed endpoint below.
        }
      }
    }
    if (!mounted) return;
    if (manifest == null) {
      setState(() {
        _selectedPeer = currentPeer;
        _connecting = false;
        final l10n = AppLocalizations.of(context)!;
        _error = unavailable
            ? '${l10n.connectionFailed} (${currentPeer.host}:${currentPeer.port})'
            : l10n.deviceSyncPinError;
      });
      return;
    }
    // Secrets require explicit selection on every manual transfer.
    final pre = <SyncCategory>{
      for (final c in SyncCategory.values)
        if (c != SyncCategory.secrets && manifest.countFor(c) > 0) c,
    };
    setState(() {
      _connecting = false;
      _selectedPeer = currentPeer;
      _manifest = manifest;
      _selected
        ..clear()
        ..addAll(pre);
    });
  }

  Future<void> _runImport() async {
    final peer = _selectedPeer;
    if (peer == null || _selected.isEmpty) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final activeProfileId = await ref.read(activeProfileIdProvider.future);
      final result = await _svc.pullAndApply(
        peer: peer,
        pin: _pinController.text.trim(),
        cats: _selected,
        activeProfileId: activeProfileId,
      );
      if (!mounted) return;
      // Re-read settings from disk FIRST so any settings the import
      // wrote (bypassing the notifier) are reflected before we layer
      // the auto-sync flag on top — otherwise the stale in-memory
      // state would clobber them.
      ref.read(settingsProvider.notifier).reload();
      // Optionally pair the two devices for future auto-sync.
      if (_remember) {
        await _svc.establishTrust(peer, _pinController.text.trim());
        if (mounted) {
          ref
              .read(settingsProvider.notifier)
              .updateSettings(
                ref.read(settingsProvider).copyWith(autoSyncEnabled: true),
              );
          await _svc.startAutoServer();
        }
      }
      if (!mounted) return;
      // Refresh everything else the import may have touched.
      ref.invalidate(savedAccountsProvider);
      ref.invalidate(currentAccountProvider);
      ref.invalidate(activeProfileIdProvider);
      ref.invalidate(profilesListProvider);
      setState(() {
        _importing = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = AppLocalizations.of(context)!.deviceSyncPinError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: Text(l10n.deviceSync),
        backgroundColor: AppColors.surface(context),
        leading: BackButton(
          onPressed: () {
            if (_mode == _Mode.sending) {
              _leaveSendMode();
            } else if (_mode == _Mode.receiving) {
              _resetReceive();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: switch (_mode) {
          _Mode.chooser => _buildChooser(l10n),
          _Mode.sending => _buildSending(l10n),
          _Mode.receiving => _buildReceiving(l10n),
        },
      ),
    );
  }

  // ── Chooser ──────────────────────────────────────────────────────────────

  Widget _buildChooser(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.deviceSyncDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              _BigActionCard(
                icon: Icons.upload,
                title: l10n.deviceSyncSend,
                subtitle: l10n.deviceSyncSendHint,
                onTap: _enterSendMode,
              ),
              const SizedBox(height: 14),
              _BigActionCard(
                icon: Icons.download,
                title: l10n.deviceSyncReceive,
                subtitle: l10n.deviceSyncReceiveHint,
                onTap: () => setState(() => _mode = _Mode.receiving),
              ),
              const SizedBox(height: 20),
              // Auto-sync toggle — only meaningful once devices have
              // paired, but we let the user pre-enable it too.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  value: ref.watch(settingsProvider).autoSyncEnabled,
                  activeThumbColor: AppColors.primary,
                  title: Text(
                    l10n.deviceSyncAuto,
                    style: const TextStyle(color: AppColors.textDark),
                  ),
                  subtitle: Text(
                    l10n.deviceSyncAutoDesc,
                    style: const TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: (v) async {
                    ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                          ref
                              .read(settingsProvider)
                              .copyWith(autoSyncEnabled: v),
                        );
                    if (v) {
                      await _svc.startAutoServer();
                    } else {
                      await _svc.stopAutoServer();
                    }
                  },
                ),
              ),
              // Paired devices — each removable — + manual "sync now".
              if (_svc.hasTrustedPeers) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.deviceSyncPaired(_svc.trustedPeers.length),
                    style: const TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (final p in _svc.trustedPeers)
                        ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.devices,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          title: Text(
                            p.name.isEmpty ? p.deviceId : p.name,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.link_off,
                              color: Colors.red.shade400,
                              size: 20,
                            ),
                            tooltip: l10n.deviceSyncForget,
                            onPressed: () => _forgetPeer(p),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _syncingNow ? null : _syncNow,
                    icon: _syncingNow
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.sync),
                    label: Text(l10n.deviceSyncNow),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Sending ────────────────────────────────────────────────────────────

  Widget _buildSending(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_tethering,
                color: AppColors.primary,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.deviceSyncSendReady,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              if (_startingServer || _pin == null)
                const CircularProgressIndicator(color: AppColors.primary)
              else ...[
                Text(
                  l10n.deviceSyncPin,
                  style: const TextStyle(
                    color: AppColors.textSecondaryDark,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevatedDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: Text(
                    _pin!,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.deviceSyncSendWaiting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondaryDark,
                    fontSize: 13,
                  ),
                ),
                if (_localIps.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    l10n.deviceSyncThisAddress,
                    style: const TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final ip in _localIps)
                    SelectableText(
                      ip,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.deviceSyncThisAddressHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textTertiaryDark,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 28),
              TextButton(onPressed: _leaveSendMode, child: Text(l10n.cancel)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Receiving ──────────────────────────────────────────────────────────

  Widget _buildReceiving(AppLocalizations l10n) {
    if (_result != null) return _buildDone(l10n);
    if (_manifest != null) return _buildSelect(l10n);
    if (_selectedPeer != null) return _buildPinEntry(l10n);
    return _buildPeerList(l10n);
  }

  Widget _buildPeerList(AppLocalizations l10n) {
    return StreamBuilder<List<SyncPeer>>(
      stream: _peerStream ??= _svc.discoverPeers(),
      builder: (context, snap) {
        final peers = snap.data ?? const <SyncPeer>[];
        final done = snap.connectionState == ConnectionState.done;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  if (!done)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    const Icon(
                      Icons.devices,
                      color: AppColors.textSecondaryDark,
                      size: 18,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      done
                          ? l10n.deviceSyncSelectDevice
                          : l10n.deviceSyncSearching,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (done)
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: AppColors.textSecondaryDark,
                      ),
                      onPressed: () => setState(() => _peerStream = null),
                      tooltip: l10n.castSearchAgain,
                    ),
                ],
              ),
            ),
            if (peers.isEmpty && done)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.deviceSyncNoPeers,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: peers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = peers[i];
                    return Card(
                      color: AppColors.surfaceDark,
                      child: ListTile(
                        leading: const Icon(Icons.tv, color: AppColors.primary),
                        title: Text(
                          p.name,
                          style: const TextStyle(color: AppColors.textDark),
                        ),
                        subtitle: Text(
                          p.host,
                          style: const TextStyle(
                            color: AppColors.textTertiaryDark,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppColors.textSecondaryDark,
                        ),
                        onTap: () => setState(() {
                          _peerStream = null;
                          _selectedPeer = p;
                        }),
                      ),
                    );
                  },
                ),
              ),
            // Fallback for networks that block multicast/broadcast/mDNS:
            // type the address shown on the sending device.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _enterAddressManually(l10n),
                  icon: const Icon(Icons.dialpad),
                  label: Text(l10n.deviceSyncManualEntry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enterAddressManually(AppLocalizations l10n) async {
    final peer = await showDialog<SyncPeer>(
      context: context,
      builder: (_) => const _ManualAddressDialog(),
    );
    if (peer == null || !mounted) return;
    setState(() {
      _peerStream = null;
      _error = null;
      _selectedPeer = peer;
    });
  }

  Widget _buildPinEntry(AppLocalizations l10n) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.password, color: AppColors.primary, size: 48),
              const SizedBox(height: 16),
              Text(
                l10n.deviceSyncEnterPin,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedPeer?.name ?? '',
                style: const TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 28,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiaryDark,
                    letterSpacing: 8,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _connectToPeer(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_connecting || _pinController.text.trim().length < 4)
                      ? null
                      : _connectToPeer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _connecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.deviceSyncConnect),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _selectedPeer = null;
                  _error = null;
                  _pinController.clear();
                }),
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelect(AppLocalizations l10n) {
    final m = _manifest!;
    final rows = <_SyncCatRow>[
      _SyncCatRow(SyncCategory.account, l10n.deviceSyncCatAccount, m.accounts),
      _SyncCatRow(
        SyncCategory.profiles,
        l10n.deviceSyncCatProfiles,
        m.profiles,
      ),
      _SyncCatRow(
        SyncCategory.favorites,
        l10n.deviceSyncCatFavorites,
        m.favorites,
      ),
      _SyncCatRow(
        SyncCategory.progress,
        l10n.deviceSyncCatProgress,
        m.progress,
      ),
      _SyncCatRow(
        SyncCategory.enrichment,
        l10n.deviceSyncCatEnrichment,
        m.enrichment,
      ),
      _SyncCatRow(
        SyncCategory.settings,
        l10n.deviceSyncCatSettings,
        m.hasSettings ? 1 : 0,
      ),
      _SyncCatRow(
        SyncCategory.secrets,
        l10n.deviceSyncCatSecrets,
        m.hasSecrets ? 1 : 0,
      ),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.deviceSyncSelectData,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final r in rows)
                if (r.count > 0)
                  CheckboxListTile(
                    value: _selected.contains(r.cat),
                    activeColor: AppColors.primary,
                    title: Text(
                      r.label,
                      style: const TextStyle(color: AppColors.textDark),
                    ),
                    subtitle: r.cat == SyncCategory.secrets
                        ? Text(l10n.deviceSyncSecretsHint)
                        : r.cat == SyncCategory.settings
                        ? null
                        : Text(
                            '${r.count}',
                            style: const TextStyle(
                              color: AppColors.textTertiaryDark,
                              fontSize: 12,
                            ),
                          ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(r.cat);
                      } else {
                        _selected.remove(r.cat);
                      }
                    }),
                  ),
            ],
          ),
        ),
        CheckboxListTile(
          value: _remember,
          activeColor: AppColors.primary,
          title: Text(
            l10n.deviceSyncRemember,
            style: const TextStyle(color: AppColors.textDark, fontSize: 14),
          ),
          onChanged: (v) => setState(() => _remember = v ?? false),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_importing || _selected.isEmpty) ? null : _runImport,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_done),
              label: Text(
                _importing ? l10n.deviceSyncImporting : l10n.deviceSyncStart,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDone(AppLocalizations l10n) {
    final r = _result!;
    final parts = <String>[
      if (r.accounts > 0) '${r.accounts} ${l10n.deviceSyncCatAccount}',
      if (r.profiles > 0) '${r.profiles} ${l10n.deviceSyncCatProfiles}',
      if (r.favorites > 0) '${r.favorites} ${l10n.deviceSyncCatFavorites}',
      if (r.progress > 0) '${r.progress} ${l10n.deviceSyncCatProgress}',
      if (r.settings) l10n.deviceSyncCatSettings,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.deviceSyncDone,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                parts.isEmpty ? '—' : parts.join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (widget.onFinished != null) {
                      widget.onFinished!.call();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(l10n.deviceSyncFinish),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the sender's IP address (optionally `ip:port`). Owns its text
/// controller so it is disposed with the dialog, after the exit animation.
class _ManualAddressDialog extends StatefulWidget {
  const _ManualAddressDialog();

  @override
  State<_ManualAddressDialog> createState() => _ManualAddressDialogState();
}

class _ManualAddressDialogState extends State<_ManualAddressDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final peer = SyncPeer.fromManualInput(_controller.text);
    if (peer == null) {
      setState(
        () => _error = AppLocalizations.of(context)!.deviceSyncAddressInvalid,
      );
      return;
    }
    Navigator.of(context).pop(peer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.surface(context),
      title: Text(l10n.deviceSyncManualEntry),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deviceSyncManualHint,
            style: const TextStyle(
              color: AppColors.textSecondaryDark,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '192.168.1.20',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.deviceSyncConnect)),
      ],
    );
  }
}

class _SyncCatRow {
  final SyncCategory cat;
  final String label;
  final int count;
  const _SyncCatRow(this.cat, this.label, this.count);
}

class _BigActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondaryDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
