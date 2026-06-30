import 'package:cast/device.dart';
import 'package:flutter/material.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/services/cast_service.dart';
import 'package:lifeostv/data/services/dlna_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Tagged union for the device picker — keeps Chromecast and DLNA results
/// in the same list while preserving the original device object so the
/// onTap dispatcher knows which service to call.
sealed class _PickerEntry {
  const _PickerEntry();
  String get displayName;
  String get subtitle;
  String get badge;
  Color get badgeColor;
}

class _CastPickerEntry extends _PickerEntry {
  final CastDevice device;
  const _CastPickerEntry(this.device);
  @override
  String get displayName => device.name;
  @override
  String get subtitle => device.host;
  @override
  String get badge => 'Chromecast';
  @override
  Color get badgeColor => const Color(0xFF4285F4); // Google blue
}

class _DlnaPickerEntry extends _PickerEntry {
  final DlnaDevice device;
  const _DlnaPickerEntry(this.device);
  @override
  String get displayName => device.displayName;
  @override
  String get subtitle => device.controlUrl.host;
  @override
  String get badge => 'DLNA';
  @override
  Color get badgeColor => const Color(0xFF7B1FA2); // Purple — DLNA brand-ish
}

/// Combined cast button. Tap → opens a picker that lists every Chromecast
/// AND every DLNA / UPnP MediaRenderer on the LAN. Glows when either
/// transport is currently connected.
class CastButton extends StatefulWidget {
  /// Called when EITHER transport starts playing remotely (local player
  /// should pause).
  final VoidCallback? onCastStarted;

  /// Called when the remote session ends (local player should resume).
  final VoidCallback? onCastStopped;

  const CastButton({
    super.key,
    this.onCastStarted,
    this.onCastStopped,
  });

  @override
  State<CastButton> createState() => _CastButtonState();
}

class _CastButtonState extends State<CastButton> {
  /// Last surfaced cast load-error, so the SnackBar fires once per failure.
  String? _shownError;

  @override
  void initState() {
    super.initState();
    CastService.instance.stateNotifier.addListener(_onCastStateChanged);
  }

  @override
  void dispose() {
    CastService.instance.stateNotifier.removeListener(_onCastStateChanged);
    super.dispose();
  }

  /// Surface a one-time message when the Chromecast receiver rejects the
  /// media (unsupported container/codec — e.g. a raw .mkv or AC-3 audio
  /// the Default Media Receiver can't decode). Otherwise the cast just
  /// shows silent/blank video with no explanation.
  void _onCastStateChanged() {
    final err = CastService.instance.state.loadError;
    if (err == null) {
      _shownError = null;
      return;
    }
    if (err == _shownError || !mounted) return;
    _shownError = err;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.castUnsupportedMedia),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cast = CastService.instance;
    final dlna = DlnaService.instance;

    // Single button reflects "any remote session active"; we listen to
    // both notifiers and merge.
    return ValueListenableBuilder<CastState>(
      valueListenable: cast.stateNotifier,
      builder: (context, castState, _) {
        return ValueListenableBuilder<DlnaState>(
          valueListenable: dlna.stateNotifier,
          builder: (context, dlnaState, _) {
            final connected = castState.isConnected || dlnaState.isConnected;
            return IconButton(
              icon: Icon(
                connected ? Icons.cast_connected : Icons.cast,
                color: connected ? AppColors.primary : Colors.white70,
                size: 20,
              ),
              tooltip: AppLocalizations.of(context)!.castDevices,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () {
                if (connected) {
                  _showConnectedSheet(context, castState, dlnaState);
                } else {
                  _showDevicePicker(context);
                }
              },
            );
          },
        );
      },
    );
  }

  void _showDevicePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DevicePickerSheet(
        onCastSelected: (device) async {
          // Capture messenger + l10n BEFORE pop so the feedback
          // snackbars survive the sheet's context being torn down.
          final messenger = ScaffoldMessenger.of(context);
          final l10n = AppLocalizations.of(context)!;
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.castConnecting(device.name)),
              duration: const Duration(seconds: 16),
            ),
          );
          final ok = await CastService.instance.connectToDevice(device);
          messenger.hideCurrentSnackBar();
          if (ok) {
            widget.onCastStarted?.call();
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.castConnectedTo(device.name)),
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            // Connect failed (timeout / receiver refused / device off
            // the network). Tell the user instead of silently leaving
            // local playback running with no explanation.
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.castFailed),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
        onDlnaSelected: (device) {
          final messenger = ScaffoldMessenger.of(context);
          final l10n = AppLocalizations.of(context)!;
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.castConnecting(device.displayName)),
              duration: const Duration(seconds: 4),
            ),
          );
          DlnaService.instance.connectTo(device);
          // The player's _onCastStarted drives the DLNA LOAD and shows
          // its own success / failure feedback (it knows whether the
          // TV actually started playing).
          widget.onCastStarted?.call();
        },
      ),
    );
  }

  void _showConnectedSheet(
    BuildContext context,
    CastState castState,
    DlnaState dlnaState,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final l10n = AppLocalizations.of(sheetCtx)!;
        // Both transports could in principle be connected at once — show
        // whichever is active and let the user disconnect.
        final showingCast = castState.isConnected;
        final deviceLabel = showingCast
            ? (castState.device?.name ?? l10n.castDevices)
            : (dlnaState.device?.displayName ?? l10n.castDevices);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cast_connected, color: AppColors.primary, size: 40),
              const SizedBox(height: 12),
              Text(
                deviceLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    if (showingCast) {
                      await CastService.instance.disconnect();
                    } else {
                      await DlnaService.instance.disconnect();
                    }
                    widget.onCastStopped?.call();
                  },
                  icon: const Icon(Icons.close),
                  label: Text(l10n.castDisconnect),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
//  Device picker bottom sheet — Chromecast + DLNA in one list
// ---------------------------------------------------------------------------

class _DevicePickerSheet extends StatefulWidget {
  final void Function(CastDevice device) onCastSelected;
  final void Function(DlnaDevice device) onDlnaSelected;

  const _DevicePickerSheet({
    required this.onCastSelected,
    required this.onDlnaSelected,
  });

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  List<_PickerEntry> _entries = [];
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  /// Discover Chromecast (mDNS) and DLNA (SSDP) in parallel — they run on
  /// different transports so neither blocks the other. We surface results
  /// together as soon as both finish.
  Future<void> _search() async {
    setState(() {
      _searching = true;
      _entries = [];
    });

    final results = await Future.wait([
      CastService.instance.discoverDevices(timeout: const Duration(seconds: 5)),
      DlnaService.instance.discoverDevices(timeout: const Duration(seconds: 5)),
    ]);

    if (!mounted) return;

    final cast = (results[0] as List<CastDevice>)
        .map((d) => _CastPickerEntry(d) as _PickerEntry);
    final dlna = (results[1] as List<DlnaDevice>)
        .map((d) => _DlnaPickerEntry(d) as _PickerEntry);

    setState(() {
      _entries = [...cast, ...dlna];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.cast, color: Colors.white70, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.castDevices,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!_searching)
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                  onPressed: _search,
                  tooltip: l10n.castSearchAgain,
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_searching) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.castSearching,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ] else if (_entries.isEmpty) ...[
            const SizedBox(height: 24),
            const Icon(Icons.cast, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              l10n.castNoDevices,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.castSearchAgain),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            const SizedBox(height: 16),
          ] else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return ListTile(
                    leading: Icon(
                      entry is _DlnaPickerEntry ? Icons.tv : Icons.cast,
                      color: Colors.white54,
                    ),
                    title: Text(
                      entry.displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      entry.subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: entry.badgeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.badge,
                        style: TextStyle(
                          color: entry.badgeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => switch (entry) {
                      _CastPickerEntry e => widget.onCastSelected(e.device),
                      _DlnaPickerEntry e => widget.onDlnaSelected(e.device),
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
