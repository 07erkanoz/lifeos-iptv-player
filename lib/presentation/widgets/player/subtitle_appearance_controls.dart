import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';

/// Subtitle visual controls (font size, color, bold, background) as a
/// single Consumer widget. Used by both the Settings → Subtitle
/// Appearance section and the in-player track picker so the user can
/// adjust subtitle look while a stream is playing without leaving the
/// player. Both surfaces read/write the same providers so changes
/// are live + persistent.
///
/// Layout adapts to [compact]:
/// - compact:false (Settings) — full cards, large preview, generous
///   spacing.
/// - compact:true (Player overlay) — denser sliders + a tighter row
///   of color swatches that fits inside the existing track-picker
///   dialog without scroll growth.
class SubtitleAppearanceControls extends ConsumerWidget {
  final bool compact;

  /// Optional rebuild callback fired after each settings write. The
  /// player passes a hook here so its outer Video widget rebuilds
  /// with the fresh SubtitleViewConfiguration (otherwise the live
  /// preview slider doesn't reflect on the actual rendered subtitle
  /// until the next frame for unrelated reasons).
  final VoidCallback? onChanged;

  const SubtitleAppearanceControls({
    super.key,
    this.compact = false,
    this.onChanged,
  });

  static const _palette = <String, Color>{
    '#FFFFFF': Color(0xFFFFFFFF),
    '#FFFF00': Color(0xFFFFFF00),
    '#00FF00': Color(0xFF00FF00),
    '#00FFFF': Color(0xFF00FFFF),
    '#FF4444': Color(0xFFFF4444),
    '#4488FF': Color(0xFF4488FF),
    '#FF8800': Color(0xFFFF8800),
    '#FF44FF': Color(0xFFFF44FF),
  };

  static Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void update(AppSettings Function(AppSettings) fn) {
      notifier.updateSettings(fn(settings));
      onChanged?.call();
    }

    final fontSize = settings.subtitleFontSize.toDouble().clamp(20.0, 110.0);

    final fontSizeRow = _LabeledSlider(
      icon: Icons.format_size,
      label: l10n.subtitleFontSize,
      valueText: '${fontSize.round()}',
      value: fontSize,
      min: 20,
      max: 110,
      divisions: 18,
      onChanged: (v) => update(
        (s) => s.copyWith(subtitleFontSize: v.round()),
      ),
      compact: compact,
    );

    final colorRow = _ColorSwatchRow(
      selectedHex: settings.subtitleColor,
      palette: _palette,
      label: l10n.subtitleColor,
      onPick: (hex) => update((s) => s.copyWith(subtitleColor: hex)),
      compact: compact,
    );

    final boldToggle = _InlineSwitch(
      icon: Icons.format_bold,
      label: l10n.subtitleBold,
      value: settings.subtitleBold,
      onChanged: (v) => update((s) => s.copyWith(subtitleBold: v)),
      compact: compact,
    );

    final backgroundToggle = _InlineSwitch(
      icon: Icons.rectangle_outlined,
      label: l10n.subtitleBackground,
      subtitle: l10n.subtitleBackgroundDesc,
      value: settings.subtitleBackgroundEnabled,
      onChanged: (v) =>
          update((s) => s.copyWith(subtitleBackgroundEnabled: v)),
      compact: compact,
    );

    final preview = _Preview(
      text: 'Altyazı Örneği',
      fontSize: settings.subtitleFontSize.toDouble().clamp(12, 36),
      color: _hexToColor(settings.subtitleColor),
      bold: settings.subtitleBold,
      background: settings.subtitleBackgroundEnabled,
    );

    if (compact) {
      // Player overlay: vertical stack, denser spacing, no card chrome
      // — the picker dialog already provides the surface.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fontSizeRow,
          const SizedBox(height: 4),
          colorRow,
          const SizedBox(height: 4),
          boldToggle,
          backgroundToggle,
        ],
      );
    }

    // Settings layout: card-wrapped sections, large preview.
    final cardColor =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor =
        isDark ? AppColors.borderDark : AppColors.borderLight;
    BoxDecoration card() => BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fontSizeRow,
              const SizedBox(height: 8),
              Center(child: preview),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: card(),
          child: colorRow,
        ),
        const SizedBox(height: 16),
        boldToggle,
        const SizedBox(height: 8),
        backgroundToggle,
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final bool compact;
  const _LabeledSlider({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: compact ? 13 : null,
      color: compact
          ? AppColors.textSecondaryDark
          : (isDark ? AppColors.textDark : AppColors.textLight),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            icon,
            color: compact ? AppColors.textTertiaryDark : AppColors.primary,
            size: compact ? 16 : 20,
          ),
          const SizedBox(width: 8),
          Text(label, style: labelStyle),
          const Spacer(),
          Text(
            valueText,
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 16,
            ),
          ),
        ]),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.primary,
          label: valueText,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  final String selectedHex;
  final Map<String, Color> palette;
  final String label;
  final ValueChanged<String> onPick;
  final bool compact;
  const _ColorSwatchRow({
    required this.selectedHex,
    required this.palette,
    required this.label,
    required this.onPick,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: compact ? 13 : null,
      color: compact
          ? AppColors.textSecondaryDark
          : (isDark ? AppColors.textDark : AppColors.textLight),
    );
    final size = compact ? 28.0 : 40.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            Icons.palette_outlined,
            color: compact ? AppColors.textTertiaryDark : AppColors.primary,
            size: compact ? 16 : 20,
          ),
          const SizedBox(width: 8),
          Text(label, style: labelStyle),
        ]),
        SizedBox(height: compact ? 8 : 12),
        Wrap(
          spacing: compact ? 8 : 10,
          runSpacing: compact ? 8 : 10,
          children: palette.entries.map((e) {
            final isSelected =
                selectedHex.toUpperCase() == e.key.toUpperCase();
            return GestureDetector(
              onTap: () => onPick(e.key),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: e.value,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: isSelected ? 3 : 0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color: e.value.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: compact ? 14 : 20,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _InlineSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool compact;
  const _InlineSwitch({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(
      color: compact
          ? AppColors.textSecondaryDark
          : (isDark ? AppColors.textDark : AppColors.textLight),
      fontSize: compact ? 13 : null,
      fontWeight: compact ? FontWeight.w600 : null,
    );
    if (compact) {
      return Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiaryDark),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: labelStyle)),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      );
    }
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.primary),
      title: Text(label, style: labelStyle),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style:
                  const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13))
          : null,
      value: value,
      activeThumbColor: AppColors.primary,
      onChanged: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    );
  }
}

class _Preview extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color color;
  final bool bold;
  final bool background;
  const _Preview({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.bold,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          backgroundColor: background ? Colors.black54 : Colors.transparent,
        ),
      ),
    );
  }
}
