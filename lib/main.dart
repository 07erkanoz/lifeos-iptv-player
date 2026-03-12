import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/config/router.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/player/pip_overlay.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/gpu_detector.dart';
import 'package:lifeostv/utils/platform_utils.dart';

/// Pre-loaded SharedPreferences provider - overridden in main()
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

/// Whether this device is an Android TV (leanback) device
final isTvDeviceProvider = Provider<bool>((ref) => false);

Future<bool> _detectAndroidTV() async {
  if (!Platform.isAndroid) return false;
  try {
    const channel = MethodChannel('com.lifeostv.lifeostv/platform');
    final result = await channel.invokeMethod<bool>('isTV');
    return result ?? false;
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Desktop window setup (Windows/Linux/macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(900, 500),
      center: true,
      backgroundColor: const Color(0xFF101012),
      titleBarStyle: TitleBarStyle.hidden,
      title: 'LifeOs TV',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // macOS: hide native traffic light buttons since we provide our own
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
            windowButtonVisibility: false);
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Pre-load SharedPreferences to eliminate async waterfall
  final prefs = await SharedPreferences.getInstance();

  // Detect if running on Android TV
  final isTV = await _detectAndroidTV();
  PlatformHelper.setTVDevice(isTV);

  // Pre-cache GPU info so player init is instant
  GpuDetector.detect();

  // On Android TV: force landscape. On mobile: allow all orientations
  if (Platform.isAndroid) {
    if (isTV) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isTvDeviceProvider.overrideWithValue(isTV),
      ],
      child: const LifeosApp(),
    ),
  );
}

class LifeosApp extends ConsumerWidget {
  const LifeosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    final themeMode = settings.themeMode;
    final locale = settings.language != AppLanguage.system
        ? Locale(settings.language.name)
        : null;

    return MaterialApp.router(
      routerConfig: router,
      title: 'LifeOs TV',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (isDesktopPipSupported) const FloatingPipOverlay(),
          ],
        );
        return _DesktopWindowFrame(child: content);
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('tr'),
        Locale('de'),
        Locale('fr'),
        Locale('es'),
        Locale('ar'),
        Locale('ru'),
        Locale('ku'),
      ],
      locale: locale,
      themeMode: themeMode == AppThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
    );
  }
}

class _DesktopWindowFrame extends StatefulWidget {
  final Widget child;

  const _DesktopWindowFrame({required this.child});

  @override
  State<_DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<_DesktopWindowFrame>
    with WindowListener {
  static const double _desktopCornerRadius = 14;
  bool _isFullScreen = false;
  bool _isMaximized = false;

  bool get _shouldRoundCorners =>
      isDesktopPlatform && !_isFullScreen && !_isMaximized;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      _syncWindowState();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncWindowState() async {
    final isFullScreen = await windowManager.isFullScreen();
    final isMaximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() {
      _isFullScreen = isFullScreen;
      _isMaximized = isMaximized;
    });
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return widget.child;
    }

    final content = ColoredBox(
      color: AppColors.backgroundDark,
      child: widget.child,
    );

    // Always keep ClipRRect in the tree (with radius 0 when not rounding)
    // so that toggling fullscreen/maximize doesn't rebuild the entire
    // widget subtree — which would destroy and recreate the Video widget's
    // OpenGL texture, crashing the renderer on Linux.
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        _shouldRoundCorners ? _desktopCornerRadius : 0,
      ),
      clipBehavior: _shouldRoundCorners ? Clip.antiAlias : Clip.none,
      child: content,
    );
  }
}
