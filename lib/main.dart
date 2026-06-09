import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import 'package:lifeostv/core/system_ui.dart';
import 'package:lifeostv/core/playback_signal.dart';
import 'package:lifeostv/data/services/lan_sync_service.dart';
import 'package:lifeostv/data/services/catalog_enrichment_runner.dart';
import 'package:lifeostv/data/services/catalog_embedding_runner.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/content_embeddings_repository.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/widgets/content/live_now_on_air_rail.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart'
    show activeProfileIdProvider;
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/widgets/player/pip_overlay.dart';
import 'package:lifeostv/presentation/widgets/player/pip_state.dart';
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

  // Cap Flutter's global image cache so poster/logo/thumbnail accumulation
  // between episodes can't spiral into OOM on Android.
  PaintingBinding.instance.imageCache
    ..maximumSize = 150
    ..maximumSizeBytes = 60 * 1024 * 1024;

  // Desktop window setup (Windows/Linux/macOS)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(900, 500),
      center: true,
      backgroundColor: Platform.isLinux
          ? const Color(0x00000000)
          : const Color(0xFF101012),
      titleBarStyle: TitleBarStyle.hidden,
      title: 'LifeOs TV',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
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

class LifeosApp extends ConsumerStatefulWidget {
  const LifeosApp({super.key});

  @override
  ConsumerState<LifeosApp> createState() => _LifeosAppState();
}

class _LifeosAppState extends ConsumerState<LifeosApp>
    with WidgetsBindingObserver {
  Timer? _enrichTimer;
  Timer? _syncTimer;
  bool _autoSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Kick the LAN auto-sync once the first frame is up (providers
    // ready, context available).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoSync();
      _maybeEnrichCatalog();
      _maybeSyncEpg();
    });
    // Periodic background two-way sync while the app is open. Every
    // pass is fire-and-forget off the UI thread (network + Drift),
    // guarded by `_autoSyncInFlight`, and no-ops instantly when
    // auto-sync is off or no peer is paired — so it never slows the
    // app. 5 min is frequent enough that favourites/progress/hidden-
    // category changes propagate without a manual restart.
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      _maybeAutoSync();
    });
    // Keep chipping away at the catalogue while the app is open: each
    // runOnce is bounded, so this periodic nudge continues where the
    // last left off until everything is tagged (it no-ops when the
    // setting is off, there's no key, a run is in flight, or the
    // queue is empty).
    _enrichTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      _runEnrichPass();
    });
  }

  /// Background catalogue enrichment — fills missing genre/year/mood
  /// via Gemini so search/similar/dashboard rails work on sparse
  /// IPTV metadata. Gated on the setting + a Gemini key.
  void _maybeEnrichCatalog() {
    // TV-lite: no background AI catalogue work on Android TV — the
    // enrichment/embedding Drift batch writes on the main isolate were
    // a primary cause of the unusable grid/dashboard performance.
    if (PlatformHelper.isTV) return;
    if (!ref.read(settingsProvider).catalogEnrichmentEnabled) return;
    if (!ref.read(settingsProvider).hasAiKey) return;
    // Small delay so first-frame work (playlist load, dashboard rails)
    // isn't competing with enrichment HTTP on startup.
    Future<void>.delayed(const Duration(seconds: 8), () async {
      if (!mounted) return;
      await _maybeRebuildEmbeddings();
      if (!mounted) return;
      ref.read(catalogEnrichmentRunnerProvider).runOnce();
      ref.read(catalogEmbeddingRunnerProvider).runOnce();
    });
  }

  /// Current embedding *text recipe* version. Bump this whenever
  /// [_buildText] changes so stored vectors get rebuilt from the new
  /// text. v2 added plot + cast + director to the source text — the
  /// old genre-only vectors collapsed onto each other and made the
  /// "similar" rail return the same items for every title.
  static const int _embeddingTextVersion = 2;

  /// One-time-per-version wipe of [ContentEmbeddings] so the runner
  /// re-embeds everything with the new text recipe. Cheap on a paid
  /// tier; the rail keeps working off whatever's rebuilt so far.
  Future<void> _maybeRebuildEmbeddings() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final applied = prefs.getInt('embeddingTextVersion') ?? 1;
      if (applied >= _embeddingTextVersion) return;
      final cleared =
          await ref.read(contentEmbeddingsRepositoryProvider).clearAll();
      await prefs.setInt('embeddingTextVersion', _embeddingTextVersion);
      if (kDebugMode) {
        debugPrint('[embed] text recipe v$_embeddingTextVersion — '
            'cleared $cleared old vectors for rebuild');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[embed] rebuild check failed: $e');
    }
  }

  void _runEnrichPass() {
    if (PlatformHelper.isTV) return; // TV-lite: no AI catalogue work
    // Don't run Gemini HTTP + Drift batch writes on the main isolate
    // while a video is playing — that's what caused the ~45 s stutter.
    // The periodic timer keeps ticking and resumes after playback.
    if (playbackActiveNotifier.value) return;
    if (!ref.read(settingsProvider).catalogEnrichmentEnabled) return;
    if (!ref.read(settingsProvider).hasAiKey) return;
    ref.read(catalogEnrichmentRunnerProvider).runOnce();
    // Embeddings build on the enriched text — kick them in the same
    // pass. The runner only processes items that already have a genre
    // signal, so it naturally trails enrichment.
    ref.read(catalogEmbeddingRunnerProvider).runOnce();
  }

  /// Background EPG sync at startup/resume so the dashboard "on now"
  /// rail and the AI agent's live/EPG tools have data WITHOUT the user
  /// first opening Live TV and scrolling the guide. Internally
  /// throttled to once per 2h, so calling it every launch is cheap.
  void _maybeSyncEpg() {
    Future<void>.delayed(const Duration(seconds: 12), () async {
      if (!mounted) return;
      // EPG sync hits the network + writes a lot of program rows; skip
      // while a video is playing so it doesn't stutter playback.
      if (playbackActiveNotifier.value) return;
      try {
        final acc = await ref.read(currentAccountProvider.future);
        if (acc == null) return;
        final repo = ref.read(contentRepositoryProvider);
        await repo.cleanupOldPrograms();
        await repo.syncAllLiveEpg(acc.id);
        if (!mounted) return;
        ref.invalidate(liveNowOnAirProvider);
      } catch (_) {}
    });
  }

  /// When auto-sync is enabled, keep a token-gated server up so paired
  /// peers can reach us, and actively two-way-merge favourites +
  /// continue-watching with any trusted device on the LAN. Fire-and-
  /// forget — failures are silent, the next resume retries.
  void _maybeAutoSync() {
    // mDNS + Drift merges on the main isolate — skip during playback.
    if (playbackActiveNotifier.value) return;
    if (!ref.read(settingsProvider).autoSyncEnabled) return;
    final svc = ref.read(lanSyncServiceProvider);
    if (!svc.hasTrustedPeers) return;
    // Guard against overlapping passes — startup + resume + the
    // periodic timer can all fire close together. A pass does mDNS
    // discovery (~5 s) so we never want two in flight.
    if (_autoSyncInFlight) return;
    _autoSyncInFlight = true;
    () async {
      try {
        await svc.startAutoServer();
        await svc.runAutoSyncPass();
        if (!mounted) return;
        // Drift favourites/progress are stream-backed, but settings /
        // account providers aren't — nudge the ones that aren't. The
        // settings reload picks up a Gemini key adopted from a peer.
        ref.read(settingsProvider.notifier).reload();
        ref.invalidate(activeProfileIdProvider);
      } catch (_) {
      } finally {
        _autoSyncInFlight = false;
      }
    }();
  }

  @override
  void dispose() {
    _enrichTimer?.cancel();
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android restores the system bars whenever the app comes back
    // from the background (or a phone call, or recents). Without this
    // re-apply, the status bar "leaks" back in despite the user's
    // fullscreen toggle being on. Re-assert the chosen mode on resume.
    if (state == AppLifecycleState.resumed) {
      applyMobileSystemUiMode(
        fullscreen: ref.read(settingsProvider).fullscreenMode,
      );
      _maybeAutoSync();
      _runEnrichPass();
      _maybeSyncEpg();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    final themeMode = settings.themeMode;
    final locale = settings.language != AppLanguage.system
        ? Locale(settings.language.name)
        : null;

    // Apply mobile fullscreen mode every time the setting flips.
    // Mobile-only: on desktop / TV the SystemUiOverlay enum is a
    // no-op (no top status bar to hide). We call this from build()
    // so a settings toggle takes effect immediately without
    // restarting the app. Resume re-application lives in
    // didChangeAppLifecycleState.
    applyMobileSystemUiMode(fullscreen: settings.fullscreenMode);

    final pipActive = ref.watch(pipProvider) != null;

    return MaterialApp.router(
      routerConfig: router,
      title: 'LifeOs TV',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // PiP overlay floats ON TOP of the router subtree instead of
        // replacing it. We tried the swap approach earlier (return
        // PipOverlay instead of `child`) but it orphaned the entire
        // navigator: any pending Navigator.pop() got swallowed because
        // the route's State unmounted mid-call, the pushed /player
        // route on expand never mounted because the router subtree was
        // hidden, and on close the router would re-render with stale
        // routes still on its stack — producing the "frozen gray"
        // screen the user reported.
        //
        // Stacking keeps the navigator alive and rendering normally;
        // PiP just paints over it. Since the host window is shrunk to
        // 380x230 in window-mode PiP, the underlying router child is
        // entirely covered anyway, so visually it still feels like the
        // app "disappears" behind the mini player.
        return _DesktopWindowFrame(
          child: Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              if (pipUsesWindowMode && pipActive) const PipOverlay(),
            ],
          ),
        );
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
