import 'dart:io';
import 'package:lifeostv/core/platform_helper.dart';

/// Whether the current platform uses sidebar layout (desktop + Android TV)
bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux || Platform.isMacOS || PlatformHelper.isTV;

/// Whether the current platform uses bottom nav + touch (mobile phones/tablets, NOT Android TV)
bool get isMobilePlatform => (Platform.isAndroid || Platform.isIOS) && !PlatformHelper.isTV;

/// Desktop in-app PiP is only enabled on platforms where the shared player handoff is stable.
bool get isDesktopPipSupported => Platform.isWindows || Platform.isMacOS;

/// Full PiP support includes Android native PiP plus desktop in-app PiP.
bool get isPipSupported => Platform.isAndroid || isDesktopPipSupported;
