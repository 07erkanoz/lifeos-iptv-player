// Audit probes record existing defects; these are not post-fix regression tests.
// flutter test docs/release-audit-2026-10-09/audit_probe_test.dart --no-pub
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/datasources/remote/xtream_api_service.dart';
import 'package:lifeostv/data/models/tonight_recommendation.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/data/repositories/intro_marker_repository.dart';
import 'package:lifeostv/data/services/ai_instrumentation_service.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

void main() {
  final evidence = <String, Object?>{};
  tearDownAll(() {
    File(
      'docs/release-audit-2026-10-09/probe-results.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
  });
  test('Check app and framework locale coverage', () {
    evidence['locales'] = [
      for (final lang in ['en', 'tr', 'de', 'fr', 'es', 'ar', 'ru', 'ku'])
        {
          'code': lang,
          'app': AppLocalizations.delegate.isSupported(Locale(lang)),
          'material': GlobalMaterialLocalizations.delegate.isSupported(
            Locale(lang),
          ),
          'cupertino': GlobalCupertinoLocalizations.delegate.isSupported(
            Locale(lang),
          ),
          'widgets': GlobalWidgetsLocalizations.delegate.isSupported(
            Locale(lang),
          ),
        },
    ];
    expect(AppLocalizations.delegate.isSupported(const Locale('ku')), isTrue);
    expect(
      GlobalMaterialLocalizations.delegate.isSupported(const Locale('ku')),
      isFalse,
    );
    expect(
      GlobalCupertinoLocalizations.delegate.isSupported(const Locale('ku')),
      isFalse,
    );
  });
  test(
    'Ambiguous catalogue IDs cannot resolve untyped AI recommendations',
    () async {
      final root = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(root.close);
      final db = root.forAccount(1);
      for (final type in ['movie', 'series']) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(id: 'all', name: 'All', type: type),
            );
        await db
            .into(db.channels)
            .insert(
              ChannelsCompanion.insert(
                streamId: 42,
                name: 'Fixture $type',
                type: type,
                categoryId: 'all',
              ),
            );
      }
      final repo = ContentRepository(
        db,
        SyncService(db, XtreamApiService(Dio())),
        () => 1,
      );
      final rec = TonightRecommendation.fromJson({
        'streamId': 42,
        'type': 'movie',
        'reason': 'Fixture recommendation',
      })!;
      expect(await repo.getVisibleChannel(rec.streamId), isNull);
      expect(
        (await repo.getVisibleChannel(rec.streamId, type: 'movie'))?.type,
        'movie',
      );
      evidence['aiIdCollision'] = {
        'untyped': 'null',
        'typed': 'movie',
        'recommendationStoresType': false,
      };
    },
  );
  test(
    'Intro repository accepts inverted and negative timeline bounds',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = IntroMarkerRepository(db);
      await repo.setMarker(42, introStartMs: -1000, introEndMs: -5000);
      final marker = (await repo.getMarker(42))!;
      expect(marker.introStartMs, -1000);
      expect(marker.introEndMs, -5000);
      evidence['introBounds'] = {
        'acceptedStartMs': marker.introStartMs,
        'acceptedEndMs': marker.introEndMs,
      };
    },
  );
  test('Instrumentation timeout does not cancel underlying work', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    var sideEffect = false;
    final completed = Completer<void>();
    final service = AiInstrumentationService(db);
    final result = await service.record<int>(
      feature: 'audit_fixture',
      model: 'fixture',
      timeout: const Duration(milliseconds: 5),
      run: () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        sideEffect = true;
        completed.complete();
        return 1;
      },
    );
    expect(result, isNull);
    await completed.future;
    expect(sideEffect, isTrue);
    // Allow the independent telemetry write to finish before closing SQLite.
    await db.customSelect('SELECT 1').get();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await db.close();
    evidence['timeoutCancellation'] = {
      'result': null,
      'underlyingWorkCompleted': true,
    };
  });
}
