import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:lifeostv/presentation/widgets/layout/app_shell.dart';
import 'package:lifeostv/presentation/screens/settings/settings_screen.dart';
import 'package:lifeostv/presentation/screens/live/live_tv_screen.dart';
import 'package:lifeostv/presentation/screens/player/video_player_screen.dart';
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
          return VideoPlayerScreen(
            streamUrl: extras['url'],
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
            channels: extras['channels'] as List<PlayerChannel>?,
            currentChannelIndex: extras['currentChannelIndex'] as int?,
            categoryNames: extras['categoryNames'] as Map<String, String>?,
            existingPlayer: extras['existingPlayer'] as Player?,
            existingController: extras['existingController'] as VideoController?,
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
