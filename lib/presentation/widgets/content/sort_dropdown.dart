import 'package:flutter/material.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/sort_mode.dart';

/// Compact dropdown that lets the user pick a [SortMode]. Decoupled from
/// any specific provider — caller passes the current value and a setter.
/// (We took the value/onChanged shape rather than a generic provider type
/// because Riverpod 3 dropped StateProvider; NotifierProvider's generic
/// signature is verbose to thread through.)
class SortDropdown extends StatelessWidget {
  final SortMode value;
  final ValueChanged<SortMode> onChanged;

  const SortDropdown({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    String labelFor(SortMode m) {
      switch (m) {
        case SortMode.recent:
          return l10n.sortByRecent;
        case SortMode.rating:
          return l10n.sortByRating;
        case SortMode.name:
          return l10n.sortByName;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, color: AppColors.textSecondaryDark, size: 16),
          const SizedBox(width: 6),
          Text(
            '${l10n.sortBy}:',
            style: const TextStyle(
              color: AppColors.textSecondaryDark,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<SortMode>(
              value: value,
              isDense: true,
              dropdownColor: AppColors.surfaceElevatedDark,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.textSecondaryDark,
                size: 18,
              ),
              items: SortMode.values
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(labelFor(m)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
