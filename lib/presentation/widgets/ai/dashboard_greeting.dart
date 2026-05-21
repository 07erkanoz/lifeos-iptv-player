import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/gemini_service.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// One-line localised greeting that anchors the dashboard, written
/// by Gemini based on the time of day, the user's most recent
/// unfinished item, and the last few titles they've touched.
///
/// Behaviour mirrors the rest of the AI surfaces — without a key
/// the widget renders nothing (no fallback hardcoded greeting
/// either, the dashboard just starts at the hero like it always
/// did). With a key the banner appears once we've talked to
/// Gemini, and is cached in-memory for the session so navigation
/// doesn't trigger a refetch every tab switch.
class DashboardGreeting extends ConsumerStatefulWidget {
  const DashboardGreeting({super.key});

  @override
  ConsumerState<DashboardGreeting> createState() =>
      _DashboardGreetingState();
}

class _DashboardGreetingState extends ConsumerState<DashboardGreeting> {
  String? _text;
  bool _loading = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    // Defer to the next microtask so we can read providers without
    // racing the build-phase rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFetch());
  }

  Future<void> _maybeFetch() async {
    if (_attempted) return;
    final gemini = ref.read(geminiServiceProvider);
    if (gemini == null) return; // No key → no banner.
    _attempted = true;

    final db = ref.read(appDatabaseProvider);

    // Resume target: most recent unfinished playback row.
    String? resumeTitle;
    try {
      final recentRow = await (db.select(db.channels).join([
        innerJoin(
          db.playbackProgress,
          db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
              db.playbackProgress.type.equalsExp(db.channels.type),
        ),
      ])
            ..where(db.playbackProgress.position.isBiggerThanValue(0))
            ..where(db.playbackProgress.isFinished.equals(false))
            ..orderBy([
              OrderingTerm(
                  expression: db.playbackProgress.updatedAt,
                  mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (recentRow != null) {
        resumeTitle = recentRow.readTable(db.channels).name;
      }
    } catch (_) {}

    // Recent titles for pattern detection (last 5 distinct touched).
    final recentTitles = <String>[];
    try {
      final rows = await (db.select(db.channels).join([
        innerJoin(
          db.playbackProgress,
          db.playbackProgress.streamId.equalsExp(db.channels.streamId) &
              db.playbackProgress.type.equalsExp(db.channels.type),
        ),
      ])
            ..orderBy([
              OrderingTerm(
                  expression: db.playbackProgress.updatedAt,
                  mode: OrderingMode.desc),
            ])
            ..limit(5))
          .get();
      for (final row in rows) {
        final name = row.readTable(db.channels).name;
        if (!recentTitles.contains(name)) recentTitles.add(name);
      }
    } catch (_) {}

    setState(() => _loading = true);

    final now = DateTime.now();
    final timeOfDay = _timeBucket(now.hour);
    final dayOfWeek = _dayNameTr(now.weekday);
    final lang = ref.read(settingsProvider).language.name == 'system'
        ? 'tr'
        : ref.read(settingsProvider).language.name;

    final greeting = await gemini.dashboardGreeting(
      timeOfDay: timeOfDay,
      dayOfWeek: dayOfWeek,
      resumeTitle: resumeTitle,
      recentTitles: recentTitles,
      targetLanguage: lang,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _text = greeting;
    });
  }

  String _timeBucket(int hour) {
    if (hour < 6) return 'gece';
    if (hour < 12) return 'sabah';
    if (hour < 18) return 'öğle';
    return 'akşam';
  }

  String _dayNameTr(int weekday) {
    const names = {
      DateTime.monday: 'Pazartesi',
      DateTime.tuesday: 'Salı',
      DateTime.wednesday: 'Çarşamba',
      DateTime.thursday: 'Perşembe',
      DateTime.friday: 'Cuma',
      DateTime.saturday: 'Cumartesi',
      DateTime.sunday: 'Pazar',
    };
    return names[weekday] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    // No key → invisible.
    final hasAiKey = ref.watch(settingsProvider).hasAiKey;
    if (!hasAiKey) return const SizedBox.shrink();

    // Pre-fetch: invisible (we deliberately avoid a placeholder
    // pill flashing into existence).
    if (_text == null && !_loading) return const SizedBox.shrink();
    // Loading: also invisible — banner should land "fully formed"
    // rather than show a spinner above the hero.
    if (_loading) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Icon(Icons.auto_awesome,
              color: AppColors.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _text!,
              style: TextStyle(
                color: isDark ? AppColors.textDark : AppColors.textLight,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
