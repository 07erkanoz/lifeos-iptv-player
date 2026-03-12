import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'gpu_detector.dart';

/// Platform-aware MPV configuration based on detected GPU
class MpvConfig {
  /// Apply optimal MPV properties for the detected GPU
  static Future<void> applyOptimal(NativePlayer mpv, GpuInfo gpu) async {
    // ── Hardware decoding ──
    await mpv.setProperty('hwdec', gpu.hwdecMode);
    await mpv.setProperty('hwdec-codecs', 'all');

    if (Platform.isAndroid) {
      await _applyAndroid(mpv, gpu);
    } else if (Platform.isLinux) {
      await _applyLinux(mpv, gpu);
    } else if (Platform.isWindows) {
      await _applyWindows(mpv, gpu);
    }

    // ── Common: drop late frames ──
    await mpv.setProperty('framedrop', 'vo');
    await mpv.setProperty('audio-buffer', '0.1');
  }

  static Future<void> _applyAndroid(NativePlayer mpv, GpuInfo gpu) async {
    // Android: media_kit uses OpenGL ES texture rendering
    // Do NOT set vo — let media_kit manage it via its own render context

    switch (gpu.vendor) {
      case GpuVendor.qualcomm:
        // Adreno GPUs: well-optimized, enable async decode
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('interpolation', 'no');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      case GpuVendor.arm:
        // ARM Mali GPUs (MediaTek, Kirin, etc.)
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('interpolation', 'no');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      case GpuVendor.samsung:
        // Samsung Exynos (Xclipse/Mali): use copy mode, conservative settings
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('interpolation', 'no');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      case GpuVendor.nvidia:
        // NVIDIA Shield / Tegra: powerful, but stick to safe defaults
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        break;

      case GpuVendor.imgtech:
        // PowerVR: older GPUs, conservative
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('interpolation', 'no');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      default:
        // Unknown Android GPU: safe defaults
        await mpv.setProperty('video-sync', 'audio');
        await mpv.setProperty('interpolation', 'no');
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;
    }
  }

  static Future<void> _applyLinux(NativePlayer mpv, GpuInfo gpu) async {
    // Linux: media_kit uses its own OpenGL render context
    // Do NOT set vo — let media_kit manage it
    await mpv.setProperty('gpu-api', 'opengl');
    await mpv.setProperty('video-sync', 'audio');
    await mpv.setProperty('interpolation', 'no');

    switch (gpu.vendor) {
      case GpuVendor.amd:
        // AMD Radeon: VA-API via radeonsi
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      case GpuVendor.nvidia:
        // NVIDIA: nvdec, can handle better scalers
        await mpv.setProperty('scale', 'spline36');
        await mpv.setProperty('cscale', 'spline36');
        break;

      case GpuVendor.intel:
        // Intel iGPU: VA-API via iHD, lightweight scalers
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      default:
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;
    }
  }

  static Future<void> _applyWindows(NativePlayer mpv, GpuInfo gpu) async {
    switch (gpu.vendor) {
      case GpuVendor.nvidia:
        // NVIDIA: nvdec + better quality scalers
        await mpv.setProperty('scale', 'spline36');
        await mpv.setProperty('cscale', 'spline36');
        break;

      case GpuVendor.amd:
        // AMD: D3D11VA, moderate scalers
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        break;

      case GpuVendor.intel:
        // Intel iGPU: D3D11VA, lightweight
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        await mpv.setProperty('dscale', 'bilinear');
        break;

      default:
        await mpv.setProperty('scale', 'bilinear');
        await mpv.setProperty('cscale', 'bilinear');
        break;
    }
  }
}
