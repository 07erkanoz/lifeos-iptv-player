import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/services/ai_instrumentation_service.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Settings → Debug → "AI Çağrı Geçmişi".
///
/// Three panels:
///   1. **Özet** — per-feature aggregate stats over the last 24 h:
///      total calls, success rate, p50/p95 latency, timeout count.
///      Lets the user (or developer) answer "is the AI actually
///      working?" with measurements rather than vibes.
///   2. **Son Çağrılar** — most recent 100 individual log entries
///      as a live list. Stream-backed so new calls appear in real
///      time while the panel is open.
///   3. Privacy notice — log stays local, prompts/responses NOT
///      stored, only timing + counts + error codes.
///
/// No data leaves the device. The Drift table is a 1000-row ring
/// buffer trimmed by the instrumentation service itself.
class AiDebugPanel extends ConsumerWidget {
  const AiDebugPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final instrumentation = ref.watch(aiInstrumentationProvider);
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(l10n.aiCallHistory),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _PrivacyNotice(isDark: isDark),
          const SizedBox(height: 12),
          _SummarySection(instrumentation: instrumentation, isDark: isDark),
          const SizedBox(height: 20),
          Text(
            l10n.recentCalls,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          _RecentCallsList(
              instrumentation: instrumentation, isDark: isDark),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  final bool isDark;
  const _PrivacyNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline,
              color: AppColors.primary, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu kayıtlar sadece bu cihazda tutulur. Prompt veya cevap '
              'içeriği DEĞİL, sadece süre, başarı durumu ve hata kodu '
              'kaydedilir. Son 1000 çağrı saklanır.',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final AiInstrumentationService instrumentation;
  final bool isDark;
  const _SummarySection({
    required this.instrumentation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          'SON 24 SAAT — ÖZET',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<AiFeatureStats>>(
          future: instrumentation.featureStats(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              );
            }
            final stats = snapshot.data ?? const [];
            if (stats.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Henüz AI çağrısı yapılmamış. AI asistanı, arama '
                  'veya dashboard önerilerini bir kez kullan, sonra '
                  'buraya dön.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final s in stats) _FeatureStatRow(stats: s),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeatureStatRow extends StatelessWidget {
  final AiFeatureStats stats;
  const _FeatureStatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final successPct = (stats.successRate * 100).toStringAsFixed(0);
    final ok = stats.successRate >= 0.9;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ok ? Colors.greenAccent : Colors.orangeAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              stats.feature,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: _MetricCell(
              label: 'çağrı',
              value: '${stats.totalCalls}',
            ),
          ),
          Expanded(
            child: _MetricCell(
              label: 'başarı',
              value: '%$successPct',
              color: ok ? Colors.greenAccent : Colors.orangeAccent,
            ),
          ),
          Expanded(
            child: _MetricCell(
              label: 'p50',
              value: '${stats.latencyP50Ms}ms',
            ),
          ),
          Expanded(
            child: _MetricCell(
              label: 'p95',
              value: '${stats.latencyP95Ms}ms',
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MetricCell({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }
}

class _RecentCallsList extends StatelessWidget {
  final AiInstrumentationService instrumentation;
  final bool isDark;
  const _RecentCallsList({
    required this.instrumentation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AiCallLog>>(
      stream: instrumentation.watchRecent(limit: 100),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const [];
        if (logs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Henüz kayıt yok.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 13,
              ),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceDark
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              for (final l in logs) _LogRow(log: l, isDark: isDark),
            ],
          ),
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  final AiCallLog log;
  final bool isDark;
  const _LogRow({required this.log, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm:ss').format(log.createdAt);
    final Color statusColor;
    final String statusLabel;
    if (log.success) {
      statusColor = Colors.greenAccent;
      statusLabel = 'OK';
    } else if (log.timedOut) {
      statusColor = Colors.redAccent;
      statusLabel = 'TIMEOUT';
    } else {
      statusColor = Colors.orangeAccent;
      statusLabel = log.errorCode ?? 'FAIL';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              time,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              log.feature,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${log.latencyMs}ms',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
