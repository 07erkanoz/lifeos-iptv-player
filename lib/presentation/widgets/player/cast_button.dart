import 'dart:async';
import 'package:cast/device.dart';
import 'package:flutter/material.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/services/cast_service.dart';

/// Chromecast icon button for the player bottom bar.
/// Shows device picker bottom-sheet on tap. Glows when connected.
class CastButton extends StatelessWidget {
  /// Called when a cast session starts (local player should pause).
  final VoidCallback? onCastStarted;

  /// Called when a cast session ends (local player should resume).
  final VoidCallback? onCastStopped;

  const CastButton({
    super.key,
    this.onCastStarted,
    this.onCastStopped,
  });

  @override
  Widget build(BuildContext context) {
    final service = CastService.instance;

    return ValueListenableBuilder<CastState>(
      valueListenable: service.stateNotifier,
      builder: (context, castState, _) {
        return IconButton(
          icon: Icon(
            castState.isConnected ? Icons.cast_connected : Icons.cast,
            color: castState.isConnected ? AppColors.primary : Colors.white70,
            size: 20,
          ),
          tooltip: 'Chromecast',
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () {
            if (castState.isConnected) {
              _showConnectedSheet(context);
            } else {
              _showDevicePicker(context);
            }
          },
        );
      },
    );
  }

  /// Show device discovery bottom sheet.
  void _showDevicePicker(BuildContext context) {
    final service = CastService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DevicePickerSheet(
        onDeviceSelected: (device) async {
          Navigator.of(context).pop();
          final ok = await service.connectToDevice(device);
          if (ok) {
            onCastStarted?.call();
          }
        },
        castService: service,
      ),
    );
  }

  /// Show "connected" bottom sheet with disconnect option.
  void _showConnectedSheet(BuildContext context) {
    final service = CastService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, color: AppColors.primary, size: 40),
            const SizedBox(height: 12),
            Text(
              service.state.device?.name ?? 'Chromecast',
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
                onPressed: () {
                  Navigator.of(context).pop();
                  service.disconnect();
                  onCastStopped?.call();
                },
                icon: const Icon(Icons.close),
                label: const Text('Bağlantıyı Kes'),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  Device picker bottom sheet (with live search)
// ---------------------------------------------------------------------------

class _DevicePickerSheet extends StatefulWidget {
  final CastService castService;
  final void Function(CastDevice device) onDeviceSelected;

  const _DevicePickerSheet({
    required this.castService,
    required this.onDeviceSelected,
  });

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  List<CastDevice> _devices = [];
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _devices = [];
    });
    final devices = await widget.castService.discoverDevices(
      timeout: const Duration(seconds: 5),
    );
    if (mounted) {
      setState(() {
        _devices = devices;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const Expanded(
                child: Text(
                  'Chromecast Cihazları',
                  style: TextStyle(
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
                  tooltip: 'Yeniden Ara',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Content
          if (_searching) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            const Text(
              'Cihazlar aranıyor…',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ] else if (_devices.isEmpty) ...[
            const SizedBox(height: 24),
            const Icon(Icons.cast, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Chromecast cihazı bulunamadı',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Tekrar Ara'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
            const SizedBox(height: 16),
          ] else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _devices.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.tv,
                      color: Colors.white54,
                    ),
                    title: Text(
                      device.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      device.host,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => widget.onDeviceSelected(device),
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
