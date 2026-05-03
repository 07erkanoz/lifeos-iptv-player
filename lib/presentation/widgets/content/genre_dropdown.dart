import 'package:flutter/material.dart';

import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Genre picker for movies / series grids. The `null` option means "All
/// genres" (no filter). Same value/onChanged shape as SortDropdown so the
/// caller decides which provider to bind it to.
class GenreDropdown extends StatelessWidget {
  /// Currently selected genre (`null` = no filter).
  final String? value;

  /// Full list of available genres for this screen, alphabetically sorted.
  final List<String> genres;

  final ValueChanged<String?> onChanged;

  const GenreDropdown({
    super.key,
    required this.value,
    required this.genres,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // No genres in DB yet → don't render the picker (avoids a useless
    // dropdown with only "All" inside).
    if (genres.isEmpty) return const SizedBox.shrink();

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
          const Icon(
            Icons.category_outlined,
            color: AppColors.textSecondaryDark,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '${l10n.genre}:',
            style: const TextStyle(
              color: AppColors.textSecondaryDark,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              // Drop the picker back to "All" if the channels reload and
              // the previously-selected genre disappeared from the list.
              value: (value != null && genres.contains(value)) ? value : null,
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
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.all),
                ),
                ...genres.map(
                  (g) => DropdownMenuItem<String?>(value: g, child: Text(g)),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
