import 'package:flutter/services.dart';
import 'package:lifeostv/presentation/screens/settings/settings_screen.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_provider.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_branches.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/screens/search/search_screen.dart';

class _DelayedSearch extends ContentRepository {
  _DelayedSearch(AppDatabase db)
    : super(db, SyncService(db, XtreamApiService(Dio())), () => 1);
  final requests = <String, Completer<List<Channel>>>{};
  @override
  Future<List<Channel>> searchChannelsByType(
    String query,
    String type, {
    int limit = 100,
  }) => (requests[type] = Completer<List<Channel>>()).future;
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());
  testWidgets(
    'settings D-pad enters content, backs to selected section and returns to sidebar',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          rootDatabaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          geminiServiceProvider.overrideWithValue(null),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      final registry = container.read(tvFocusRegistryProvider);
      var sidebar = 0;
      registry.registerMainSidebar(() => sidebar++);
      registry.requestActivePrimary(TvBranchIndex.settings);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'SettingsNav4');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('SettingsNav4'),
      );
      expect(registry.handleBranchBack(TvBranchIndex.settings), true);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'SettingsNav4');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(sidebar, 1);
      registry.requestActivePrimary(TvBranchIndex.settings);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'SettingsNav4');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.binding.setSurfaceSize(null);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing the query invalidates outstanding plain search results',
    (tester) async {
      final repo = _DelayedSearch(db);
      final container = ProviderContainer(
        overrides: [
          rootDatabaseProvider.overrideWithValue(db),
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          contentRepositoryProvider.overrideWithValue(repo),
          geminiServiceProvider.overrideWithValue(null),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SearchScreen(),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Old result');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.requests, hasLength(3));
      await tester.enterText(find.byType(TextField).first, '');
      for (final request in repo.requests.entries) {
        request.value.complete(
          request.key == 'movie'
              ? [
                  Channel(
                    accountId: 0,
                    streamId: 1,
                    name: 'Old result',
                    type: 'movie',
                    categoryId: 'movie',
                  ),
                ]
              : [],
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
