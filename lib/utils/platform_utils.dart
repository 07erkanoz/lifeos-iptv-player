import 'dart:io';
import 'package:lifeostv/core/platform_helper.dart';

/// Whether the current platform uses sidebar layout (desktop + Android TV)
bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux || Platform.isMacOS || PlatformHelper.isTV;

/// Whether the current platform uses bottom nav + touch (mobile phones/tablets, NOT Android TV)
bool get isMobilePlatform => (Platform.isAndroid || Platform.isIOS) && !PlatformHelper.isTV;

/// PiP is supported on every desktop platform — the implementation is the
/// same window-shrink + always-on-top approach (see PipNotifier). Linux was
/// previously excluded because it used the in-app FloatingPipOverlay and
/// that path was unstable; with the window-mode rewrite all three desktops
/// share the same code.
bool get isDesktopPipSupported =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Full PiP support includes Android native PiP plus desktop window PiP.
bool get isPipSupported => Platform.isAndroid || isDesktopPipSupported;
