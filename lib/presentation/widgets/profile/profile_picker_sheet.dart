import 'package:lifeostv/presentation/widgets/profile/profile_pin_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// "Kim izliyor?" bottom sheet — Netflix's profile picker, adapted
/// to the in-app modal pattern we already use elsewhere (mood
/// picker, AI chat, spoiler shield).
///
/// Triggered from:
///   * The sidebar avatar button.
///   * App-launch onboarding (future Sprint 2c addition).
///
/// Behaviour:
///   * Lists every profile as a tappable avatar tile with name.
///   * Tap a profile → if it has a PIN, prompt for the PIN; on
///     success (or no PIN), call [profileRepositoryProvider]
///     setActiveProfile and pop.
///   * Wrong PIN → snackbar, sheet stays open.
///   * Footer offers "Profilleri yönet" which pushes the Settings
///     → Profiller route.
///
/// Focus / TV: every tile is a Focus widget with select-key
/// support so Android TV remote can navigate the picker. The
/// currently-active profile autofocuses on open.
class ProfilePickerSheet extends ConsumerStatefulWidget {
  const ProfilePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ProfilePickerSheet(),
    );
  }

  @override
  ConsumerState<ProfilePickerSheet> createState() => _ProfilePickerSheetState();
}

class _ProfilePickerSheetState extends ConsumerState<ProfilePickerSheet> {
  Future<void> _selectProfile(Profile profile) async {
    final repo = await ref.read(profileRepositoryProvider.future);
    if (!mounted) return;
    final activeId = await ref.read(activeProfileIdProvider.future);
    if (!mounted) return;
    if (profile.id == activeId) {
      // Already active — just close.
      if (mounted) Navigator.of(context).pop();
      return;
    }
    // PIN gate for kids profiles (or any profile that set one).
    if (profile.pin != null && profile.pin!.isNotEmpty) {
      final ok = await confirmProfilePin(context, profile);
      if (!ok) return; // wrong / cancelled; sheet stays open
    }
    if (!mounted) return;
    await repo.setActiveProfile(profile.id);
    if (!mounted) return;
    // Invalidate the active-id provider so every downstream
    // repository rebuilds against the new profile.
    ref.invalidate(activeProfileIdProvider);
    ref.invalidate(activeProfileProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profilesAsync = ref.watch(profilesListProvider);
    final activeIdAsync = ref.watch(activeProfileIdProvider);
    final activeId = activeIdAsync.value ?? 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.textTertiaryDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.profileSwitch,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            profilesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '$e',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
              data: (profiles) {
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: profiles.map((p) {
                    return _PickerTile(
                      profile: p,
                      isActive: p.id == activeId,
                      onTap: () => _selectProfile(p),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 14),
            // Manage button — pushes Settings → Profiller. Uses
            // OutlinedButton so it sits visually below the main
            // tiles without competing with them.
            Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Caller is responsible for routing — we just emit
                  // an intent via the standard navigation pattern.
                  // Settings opens via the sidebar; users get there
                  // by tapping the Ayarlar icon. For now we just
                  // close; future iteration may push directly.
                },
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: Text(
                  l10n.settings,
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondaryDark,
                  side: BorderSide(color: AppColors.borderDark, width: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatefulWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onTap;

  const _PickerTile({
    required this.profile,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_PickerTile> createState() => _PickerTileState();
}

class _PickerTileState extends State<_PickerTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.isActive,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? AppColors.primary
                  : (widget.isActive
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : Colors.transparent),
              width: _focused ? 2 : (widget.isActive ? 1.5 : 0),
            ),
            color: widget.isActive
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            children: [
              _ProfileAvatar(
                avatarKey: widget.profile.avatarKey,
                size: 56,
                highlight: widget.isActive,
              ),
              const SizedBox(height: 6),
              Text(
                widget.profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.isActive
                      ? AppColors.primary
                      : AppColors.textDark,
                  fontSize: 11,
                  fontWeight: widget.isActive
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              if (widget.profile.pin != null && widget.profile.pin!.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock,
                    color: AppColors.textTertiaryDark,
                    size: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable avatar circle — duplicates the palette from
/// profiles_section.dart on purpose so the picker doesn't pull in
/// the settings-only section file. If the palette grows, keep
/// both in sync.
class _ProfileAvatar extends StatelessWidget {
  final String avatarKey;
  final double size;
  final bool highlight;

  const _ProfileAvatar({
    required this.avatarKey,
    required this.size,
    this.highlight = false,
  });

  static const _avatars = <String, (IconData, Color)>{
    'default': (Icons.person, Color(0xFF6B7280)),
    'cat': (Icons.pets, Color(0xFFEC4899)),
    'panda': (Icons.face_retouching_natural, Color(0xFF10B981)),
    'rocket': (Icons.rocket_launch, Color(0xFFF59E0B)),
    'kid': (Icons.child_care, Color(0xFFFB923C)),
    'star': (Icons.star, Color(0xFFFACC15)),
    'shield': (Icons.shield_moon, Color(0xFF8B5CF6)),
    'movie': (Icons.movie_filter, Color(0xFFEF4444)),
  };

  @override
  Widget build(BuildContext context) {
    final pair = _avatars[avatarKey] ?? _avatars['default']!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pair.$2.withValues(alpha: highlight ? 0.25 : 0.15),
        border: highlight
            ? Border.all(color: pair.$2.withValues(alpha: 0.6), width: 2)
            : null,
      ),
      child: Center(
        child: Icon(pair.$1, color: pair.$2, size: size * 0.5),
      ),
    );
  }
}
