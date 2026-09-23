import 'package:lifeostv/data/services/media_request.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:go_router/go_router.dart';
import 'package:lifeostv/presentation/widgets/layout/app_shell.dart';
import 'package:lifeostv/presentation/screens/settings/settings_screen.dart';
import 'package:lifeostv/presentation/screens/live/live_tv_screen.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
import 'package:lifeostv/presentation/screens/player/tv_video_player_screen.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:lifeostv/presentation/screens/auth/landing_screen.dart';
import 'package:lifeostv/presentation/screens/auth/xtream_login_screen.dart';
import 'package:lifeostv/presentation/screens/auth/m3u_upload_screen.dart';
import 'package:lifeostv/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:lifeostv/presentation/screens/search/search_screen.dart';
import 'package:lifeostv/presentation/screens/movies/movies_screen.dart';
import 'package:lifeostv/presentation/screens/series/series_screen.dart';
import 'package:lifeostv/presentation/screens/settings/account_edit_screen.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';

part 'router.g.dart';

@riverpod
GoRouter router(Ref ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) async {
      final path = state.uri.path;

      // Allow auth routes always
      if (path.startsWith('/auth')) return null;
      // Allow player and search routes always
      if (path == '/player' || path == '/search') return null;
      // Allow account edit always
      if (path.startsWith('/account/')) return null;

      // Check if any account exists
      try {
        final accounts = await ref.read(authRepositoryProvider).getAccounts();
        if (accounts.isEmpty) {
          // No accounts -> redirect to auth landing
          return '/auth';
        }
      } catch (_) {
        // DB error (first launch) -> redirect to auth
        return '/auth';
      }

      return null; // allow navigation
    },
    routes: [
      // Auth Routes (No Shell)
      GoRoute(
        path: '/auth',
        builder: (context, state) => const LandingScreen(),
        routes: [
          GoRoute(
            path: 'xtream',
            builder: (context, state) => const XtreamLoginScreen(),
          ),
          GoRoute(
            path: 'm3u',
            builder: (context, state) => const M3UUploadScreen(),
          ),
        ],
      ),

      GoRoute(
        path: '/account/edit',
        builder: (context, state) {
          final account = state.extra as Account;
          return AccountEditScreen(account: account);
        },
      ),

      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      GoRoute(
        path: '/player',
        builder: (context, state) {
          final extras = state.extra as Map<String, dynamic>;
          // Android TV → ExoPlayer-backed player (smooth on weak TV GPUs).
          // Every other platform keeps the full media_kit VideoPlayerScreen.
          if (PlatformHelper.isTV) {
            return TvVideoPlayerScreen(
              streamUrl: extras['url'],
              httpHeaders: MediaRequest.sanitize(extras['httpHeaders']),
              streamId: extras['streamId'] as int,
              accountId: extras['accountId'] as int?,
              title: extras['title'],
              type: extras['type'] ?? VideoType.live,
              logo: extras['logo'],
              currentProgramTitle: extras['programTitle'],
              startPosition: extras['startPosition'] as Duration?,
              parentStreamId: extras['parentStreamId'] as int?,
              saveSeriesSummary: extras['saveSeriesSummary'] as bool? ?? true,
              onNextEpisode: extras['onNextEpisode'] as VoidCallback?,
              onPrevEpisode: extras['onPrevEpisode'] as VoidCallback?,
              nextEpisodeTitle: extras['nextEpisodeTitle'] as String?,
              previousEpisodeTitle: extras['previousEpisodeTitle'] as String?,
              channels: extras['channels'] as List<PlayerChannel>?,
              currentChannelIndex: extras['currentChannelIndex'] as int?,
            );
          }
          return VideoPlayerScreen(
            streamUrl: extras['url'],
              httpHeaders: MediaRequest.sanitize(extras['httpHeaders']),
            streamId: extras['streamId'] as int,
            accountId: extras['accountId'] as int?,
            title: extras['title'],
            type: extras['type'] ?? VideoType.live,
            logo: extras['logo'],
            category: extras['category'],
            currentProgramTitle: extras['programTitle'],
            programStart: extras['programStart'],
            programEnd: extras['programEnd'],
            nextEpisodeTitle: extras['nextEpisodeTitle'],
            onNextEpisode: extras['onNextEpisode'],
            onPrevEpisode: extras['onPrevEpisode'],
            plot: extras['plot'] as String?,
            genre: extras['genre'] as String?,
            year: extras['year'] as String?,
            director: extras['director'] as String?,
            cast: extras['cast'] as String?,
            rating: extras['rating'] as double?,
            startPosition: extras['startPosition'] as Duration?,
            parentStreamId: extras['parentStreamId'] as int?,
            saveSeriesSummary: extras['saveSeriesSummary'] as bool? ?? true,
            introDefaultSeconds: (extras['introDefaultSeconds'] as int?) ?? 90,
            channels: extras['channels'] as List<PlayerChannel>?,
            currentChannelIndex: extras['currentChannelIndex'] as int?,
            categoryNames: extras['categoryNames'] as Map<String, String>?,
          );
        },
      ),

      // Main App Shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          // 0: Home (Dashboard)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          // 1: Live TV
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/live',
                builder: (context, state) => const LiveTvScreen(),
              ),
            ],
          ),
          // 2: Movies
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/movies',
                builder: (context, state) => const MoviesScreen(),
              ),
            ],
          ),
          // 3: Series
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/series',
                builder: (context, state) => const SeriesScreen(),
              ),
            ],
          ),
          // 4: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
