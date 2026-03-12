import 'dart:io';
import 'package:flutter/services.dart';

/// Detected GPU vendor
enum GpuVendor { amd, nvidia, intel, qualcomm, arm, imgtech, samsung, apple, unknown }

/// GPU detection result with vendor and model info
class GpuInfo {
  final GpuVendor vendor;
  final String renderer; // e.g. "Adreno (TM) 640", "Mali-G78", "VA-API (AMD Radeon)"
  final String model;    // raw model string

  const GpuInfo({
    required this.vendor,
    this.renderer = '',
    this.model = '',
  });

  static const unknown = GpuInfo(vendor: GpuVendor.unknown);

  /// Best hwdec mode for this GPU on the current platform
  String get hwdecMode {
    if (Platform.isAndroid) {
      // Android: MediaCodec is the universal hw decoder
      // mediacodec-copy is safer (copies frames to CPU, avoids display issues)
      // mediacodec is faster (zero-copy, but can fail on some devices)
      switch (vendor) {
        case GpuVendor.qualcomm:
        case GpuVendor.arm:
        case GpuVendor.imgtech:
          return 'mediacodec';     // well-supported GPUs → zero-copy
        case GpuVendor.samsung:
          return 'mediacodec-copy'; // Exynos Mali can have issues with zero-copy
        default:
          return 'mediacodec';     // default to zero-copy, fallback handled by MPV
      }
    }
    if (Platform.isLinux) {
      switch (vendor) {
        case GpuVendor.amd:
        case GpuVendor.intel:
          return 'vaapi';          // VA-API: AMD (radeonsi) + Intel (iHD/i965)
        case GpuVendor.nvidia:
          return 'nvdec';          // NVIDIA: nvdec (newer) or cuda
        default:
          return 'auto-safe';
      }
    }
    if (Platform.isWindows) {
      switch (vendor) {
        case GpuVendor.nvidia:
          return 'nvdec';          // NVIDIA: nvdec for best performance
        case GpuVendor.amd:
        case GpuVendor.intel:
          return 'd3d11va';        // AMD/Intel: Direct3D 11 Video Acceleration
        default:
          return 'auto-safe';
      }
    }
    return 'auto-safe';
  }

  @override
  String toString() => 'GpuInfo(vendor: $vendor, renderer: $renderer, model: $model, hwdec: $hwdecMode)';
}

/// Detects GPU vendor and model on all platforms
class GpuDetector {
  static const _channel = MethodChannel('com.lifeostv.lifeostv/platform');
  static GpuInfo? _cached;

  /// Detect GPU info (cached after first call)
  static Future<GpuInfo> detect() async {
    if (_cached != null) return _cached!;
    try {
      if (Platform.isAndroid) {
        _cached = await _detectAndroid();
      } else if (Platform.isLinux) {
        _cached = _detectLinux();
      } else if (Platform.isWindows) {
        _cached = await _detectWindows();
      } else {
        _cached = GpuInfo.unknown;
      }
    } catch (_) {
      _cached = GpuInfo.unknown;
    }
    return _cached!;
  }

  /// Android: get GPU renderer from platform channel (uses GLES20.glGetString)
  static Future<GpuInfo> _detectAndroid() async {
    try {
      final result = await _channel.invokeMethod<String>('getGpuRenderer');
      if (result != null && result.isNotEmpty) {
        return _parseRenderer(result);
      }
    } catch (_) {
      // Fallback: try Build.HARDWARE and Build.BOARD
      try {
        final hardware = await _channel.invokeMethod<String>('getHardware');
        if (hardware != null) {
          return _parseHardware(hardware);
        }
      } catch (_) {}
    }
    return GpuInfo.unknown;
  }

  /// Linux: read GPU info from /sys or lspci output
  static GpuInfo _detectLinux() {
    // Method 1: Check DRI render nodes
    try {
      final dir = Directory('/sys/class/drm');
      if (dir.existsSync()) {
        for (final entry in dir.listSync()) {
          if (entry.path.contains('card0') && !entry.path.contains('-')) {
            final vendorFile = File('${entry.path}/device/vendor');
            final deviceFile = File('${entry.path}/device/device');
            if (vendorFile.existsSync()) {
              final vendorId = vendorFile.readAsStringSync().trim().toLowerCase();
              final deviceId = deviceFile.existsSync() ? deviceFile.readAsStringSync().trim() : '';
              // PCI vendor IDs
              if (vendorId.contains('1002')) {
                return GpuInfo(vendor: GpuVendor.amd, renderer: 'AMD GPU', model: deviceId);
              } else if (vendorId.contains('10de')) {
                return GpuInfo(vendor: GpuVendor.nvidia, renderer: 'NVIDIA GPU', model: deviceId);
              } else if (vendorId.contains('8086')) {
                return GpuInfo(vendor: GpuVendor.intel, renderer: 'Intel GPU', model: deviceId);
              }
            }
          }
        }
      }
    } catch (_) {}

    // Method 2: Try lspci
    try {
      final result = Process.runSync('lspci', ['-nn']);
      if (result.exitCode == 0) {
        final output = (result.stdout as String).toLowerCase();
        for (final line in output.split('\n')) {
          if (line.contains('vga') || line.contains('3d') || line.contains('display')) {
            if (line.contains('amd') || line.contains('radeon') || line.contains('1002')) {
              return GpuInfo(vendor: GpuVendor.amd, renderer: 'AMD Radeon', model: line);
            } else if (line.contains('nvidia') || line.contains('10de')) {
              return GpuInfo(vendor: GpuVendor.nvidia, renderer: 'NVIDIA', model: line);
            } else if (line.contains('intel') || line.contains('8086')) {
              return GpuInfo(vendor: GpuVendor.intel, renderer: 'Intel', model: line);
            }
          }
        }
      }
    } catch (_) {}

    return GpuInfo.unknown;
  }

  /// Windows: use wmic to get GPU info
  static Future<GpuInfo> _detectWindows() async {
    try {
      final result = await Process.run(
        'wmic',
        ['path', 'win32_VideoController', 'get', 'name', '/format:list'],
      );
      if (result.exitCode == 0) {
        final output = (result.stdout as String).toLowerCase();
        if (output.contains('nvidia') || output.contains('geforce') || output.contains('rtx') || output.contains('gtx')) {
          return GpuInfo(vendor: GpuVendor.nvidia, renderer: 'NVIDIA', model: output.trim());
        } else if (output.contains('amd') || output.contains('radeon')) {
          return GpuInfo(vendor: GpuVendor.amd, renderer: 'AMD Radeon', model: output.trim());
        } else if (output.contains('intel') || output.contains('iris') || output.contains('uhd')) {
          return GpuInfo(vendor: GpuVendor.intel, renderer: 'Intel', model: output.trim());
        }
      }
    } catch (_) {}
    return GpuInfo.unknown;
  }

  /// Parse OpenGL ES renderer string (Android)
  static GpuInfo _parseRenderer(String renderer) {
    final lower = renderer.toLowerCase();
    if (lower.contains('adreno')) {
      return GpuInfo(vendor: GpuVendor.qualcomm, renderer: renderer, model: renderer);
    } else if (lower.contains('mali')) {
      // Mali can be ARM or Samsung Exynos
      // Samsung-specific Mali variants often have "samsung" in Build.HARDWARE
      return GpuInfo(vendor: GpuVendor.arm, renderer: renderer, model: renderer);
    } else if (lower.contains('powervr') || lower.contains('img')) {
      return GpuInfo(vendor: GpuVendor.imgtech, renderer: renderer, model: renderer);
    } else if (lower.contains('nvidia') || lower.contains('tegra')) {
      return GpuInfo(vendor: GpuVendor.nvidia, renderer: renderer, model: renderer);
    } else if (lower.contains('intel')) {
      return GpuInfo(vendor: GpuVendor.intel, renderer: renderer, model: renderer);
    } else if (lower.contains('amd') || lower.contains('radeon')) {
      return GpuInfo(vendor: GpuVendor.amd, renderer: renderer, model: renderer);
    } else if (lower.contains('apple')) {
      return GpuInfo(vendor: GpuVendor.apple, renderer: renderer, model: renderer);
    } else if (lower.contains('xclipse') || lower.contains('samsung')) {
      return GpuInfo(vendor: GpuVendor.samsung, renderer: renderer, model: renderer);
    }
    return GpuInfo(vendor: GpuVendor.unknown, renderer: renderer, model: renderer);
  }

  /// Parse Android Build.HARDWARE string
  static GpuInfo _parseHardware(String hardware) {
    final lower = hardware.toLowerCase();
    if (lower.contains('qcom') || lower.contains('snapdragon')) {
      return GpuInfo(vendor: GpuVendor.qualcomm, model: hardware);
    } else if (lower.contains('exynos') || lower.contains('samsung') || lower.contains('samsungexynos')) {
      return GpuInfo(vendor: GpuVendor.samsung, model: hardware);
    } else if (lower.contains('mt') || lower.contains('mediatek')) {
      return GpuInfo(vendor: GpuVendor.arm, model: hardware); // MediaTek uses ARM Mali
    } else if (lower.contains('kirin')) {
      return GpuInfo(vendor: GpuVendor.arm, model: hardware); // Kirin uses ARM Mali
    } else if (lower.contains('tegra') || lower.contains('nvidia')) {
      return GpuInfo(vendor: GpuVendor.nvidia, model: hardware);
    }
    return GpuInfo(vendor: GpuVendor.unknown, model: hardware);
  }
}
