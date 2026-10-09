import 'package:lifeostv/presentation/controllers/episode_playlist.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_provider.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_branches.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/player_repository.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/data/services/m3u_series_catalog.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/presentation/state/navigation_state.dart';
import 'package:lifeostv/presentation/state/m3u_series_provider.dart';
import 'package:lifeostv/presentation/screens/series/series_screen.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(showTrailer: false);
}

void main() {
  testWidgets(
    'M3U detail resumes an episode and navigates to next season with direct URL',
    (tester) async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      SharedPreferences.setMockInitialValues({});
      late SharedPreferences prefs;
      late AppDatabase root, db;
      late Account account;
      late Channel selected;
      late M3uSeriesCatalog catalog;
      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        root = AppDatabase.forTesting(NativeDatabase.memory());
        await root
            .into(root.accounts)
            .insert(
              AccountsCompanion.insert(
                id: const Value(1),
                name: 'M3U',
                type: 'm3u',
                url: 'https://example.invalid/list',
                isActive: const Value(true),
              ),
            );
        db = root.forAccount(1);
        account = await root.select(root.accounts).getSingle();
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'shows',
                name: 'Shows',
                type: 'series',
              ),
            );
        for (final (id, name) in [
          (1001, 'Sample S01E01'),
          (1002, 'Sample S02E01'),
        ]) {
          await db
              .into(db.channels)
              .insert(
                ChannelsCompanion.insert(
                  streamId: id,
                  name: name,
                  type: 'series',
                  categoryId: 'shows',
                  streamUrl: Value(
                    'https://example.invalid/$id.mp4?token=exact',
                  ),
                ),
              );
        }
        final rows = await db.select(db.channels).get();
        selected = rows.first;
        catalog = buildM3uSeriesCatalog(rows);
        await PlayerRepository(
          db,
          () => 1,
        ).saveEpisodeProgress(1001, 30000, 100000);
      });
      addTearDown(() async {
        await root.close();
      });
      final service = SyncService(db, XtreamApiService(Dio()));
      late ProviderContainer container;
      await tester.runAsync(() async {
        container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            m3uSeriesCatalogProvider.overrideWith((_) => Stream.value(catalog)),
            rootDatabaseProvider.overrideWithValue(root),
            appDatabaseProvider.overrideWithValue(db),
            currentAccountProvider.overrideWith((_) async => account),
            settingsProvider.overrideWith(_Settings.new),
            geminiServiceProvider.overrideWithValue(null),
            syncServiceProvider.overrideWithValue(service),
            contentRepositoryProvider.overrideWithValue(
              ContentRepository(db, service, () => 1),
            ),
            playerRepositoryProvider.overrideWithValue(
              PlayerRepository(db, () => 1),
            ),
          ],
        );
      });
      Map<String, dynamic>? playback;
      final router = GoRouter(
        initialLocation: '/series',
        routes: [
          GoRoute(path: '/series', builder: (_, _) => const SeriesScreen()),
          GoRoute(
            path: '/player',
            builder: (_, state) {
              playback = Map<String, dynamic>.from(state.extra as Map);
              return const Scaffold(body: Text('Player destination'));
            },
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      container.read(pendingDetailChannelProvider.notifier).set(selected);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final resume = find.textContaining('S1E1').first;
      await tester.ensureVisible(resume);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(playback?['streamId'], 1001);
      expect(playback?['startPosition'], const Duration(seconds: 30));
      expect(playback?['saveSeriesSummary'], false);
      expect(playback?['url'], 'https://example.invalid/1001.mp4?token=exact');
      final playlist = playback!['episodePlaylist'] as EpisodePlaylist;
      final navigator = EpisodeNavigator(playlist);
      expect(navigator.current.streamId, 1001);
      await navigator.move(
        1,
        save: () async {},
        open: (episode) async {
          expect(episode.streamId, 1002);
          expect(episode.url, 'https://example.invalid/1002.mp4?token=exact');
        },
      );
      expect(navigator.next, isNull);
      expect(navigator.previous?.streamId, 1001);
      // The series supplies a playlist once; navigation stays in this route.
      expect(playback?['streamId'], 1001);
      router.pop();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'SeriesDetailPlay',
      );
      for (final size in [
        const Size(360, 780),
        const Size(412, 850),
        const Size(800, 900),
        const Size(900, 500),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Detail must fit $size');
      }
      expect(
        container
            .read(tvFocusRegistryProvider)
            .handleBranchBack(TvBranchIndex.series),
        true,
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('SeriesDetailPlay'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();

      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.binding.setSurfaceSize(null);
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    },
  );
}
