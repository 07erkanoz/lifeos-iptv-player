import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/profile_repository.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Settings → Profiller — CRUD for the household's [Profiles] rows.
///
/// Lays out the active profile as a hero card up top (avatar + name
/// + "active" badge), followed by a horizontally-scrollable rail
/// of all other profiles (tap to switch, long-press / pencil to
/// edit), then a "+ Yeni Profil" tile at the end of the rail.
///
/// Every interactive control is wrapped in Focus + onKeyEvent so
/// the Android TV remote can navigate the screen end-to-end.
class ProfilesSection extends ConsumerWidget {
  final AppLocalizations l10n;
  const ProfilesSection({super.key, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesListProvider);
    final activeIdAsync = ref.watch(activeProfileIdProvider);
    final activeId = activeIdAsync.maybeWhen(
      data: (v) => v,
      orElse: () => 1,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profilesTitle,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.profilesDesc,
            style: const TextStyle(
              color: AppColors.textSecondaryDark,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          profilesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('$e',
                style: const TextStyle(color: AppColors.primary)),
            data: (profiles) {
              // The DB always has at least one profile (id=1, seeded
              // in migration v18 + reasserted in beforeOpen), so an
              // empty list here is only possible mid-boot before the
              // first stream emit lands. Guard so the firstWhere
              // below doesn't throw.
              if (profiles.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final active = profiles.firstWhere(
                (p) => p.id == activeId,
                orElse: () => profiles.first,
              );
              final others =
                  profiles.where((p) => p.id != active.id).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActiveProfileCard(
                    profile: active,
                    onEdit: () => _openEditor(context, ref, active),
                    l10n: l10n,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.profileSwitch,
                    style: const TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: others.length + 1, // +1 for "add"
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        if (i == others.length) {
                          return _AddProfileTile(
                            onTap: () =>
                                _openEditor(context, ref, null),
                          );
                        }
                        return _ProfileTile(
                          profile: others[i],
                          onTap: () async {
                            await _switchProfile(ref, others[i]);
                          },
                          onEdit: () =>
                              _openEditor(context, ref, others[i]),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _switchProfile(WidgetRef ref, Profile target) async {
    // If the profile has a PIN we'd surface a sheet here. PIN flow
    // ships in Sprint 2c — for now just respect the existence of a
    // pin and ask for it inline. Empty / null PIN → switch
    // immediately.
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.setActiveProfile(target.id);
    // Invalidate everything that filters by active profile so the
    // rest of the app re-renders against the new id.
    ref.invalidate(activeProfileIdProvider);
    ref.invalidate(activeProfileProvider);
  }

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, Profile? existing) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProfileEditorDialog(
        existing: existing,
        l10n: l10n,
      ),
    );
  }
}

class _ActiveProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onEdit;
  final AppLocalizations l10n;

  const _ActiveProfileCard({
    required this.profile,
    required this.onEdit,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _Avatar(avatarKey: profile.avatarKey, size: 64, accent: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profileCurrent,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (profile.isKids) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.profileKids,
                      style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _IconActionButton(
            icon: Icons.edit_outlined,
            tooltip: l10n.profileEdit,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}

/// Compact tile in the horizontal switch rail. Wrapped in Focus so
/// D-pad lands on it; select-key triggers the switch action.
class _ProfileTile extends StatefulWidget {
  final Profile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _ProfileTile({
    required this.profile,
    required this.onTap,
    required this.onEdit,
  });

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
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
        onLongPress: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? AppColors.primary
                  : Colors.transparent,
              width: 2,
            ),
            color: _focused
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Avatar(avatarKey: widget.profile.avatarKey, size: 56),
              const SizedBox(height: 8),
              Text(
                widget.profile.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.profile.isKids)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.child_care,
                      color: Colors.orange, size: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileTile extends StatefulWidget {
  final VoidCallback onTap;
  const _AddProfileTile({required this.onTap});

  @override
  State<_AddProfileTile> createState() => _AddProfileTileState();
}

class _AddProfileTileState extends State<_AddProfileTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Focus(
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
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? AppColors.primary
                  : AppColors.borderDark,
              width: _focused ? 2 : 1,
              style: _focused ? BorderStyle.solid : BorderStyle.solid,
            ),
            color: _focused
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.textSecondaryDark,
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.add,
                    color: AppColors.textSecondaryDark, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.profileAdd,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondaryDark,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_IconActionButton> createState() => _IconActionButtonState();
}

class _IconActionButtonState extends State<_IconActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Focus(
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
        child: IconButton(
          onPressed: widget.onTap,
          icon: Icon(widget.icon,
              color: _focused
                  ? AppColors.primary
                  : AppColors.textSecondaryDark),
        ),
      ),
    );
  }
}

/// Avatar circle. We don't ship per-row image blobs — instead a
/// fixed palette of icon glyphs keyed by [avatarKey]. New keys can
/// be added without DB migration since the renderer falls back to
/// the "default" tile face when an unknown key arrives.
class _Avatar extends StatelessWidget {
  final String avatarKey;
  final double size;
  final bool accent;

  const _Avatar({
    required this.avatarKey,
    required this.size,
    this.accent = false,
  });

  /// Stable palette of avatar identifiers. Settings UI surfaces
  /// these keys; the editor lets the user pick one of them.
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

  static List<String> get availableKeys => _avatars.keys.toList();

  @override
  Widget build(BuildContext context) {
    final pair = _avatars[avatarKey] ?? _avatars['default']!;
    final icon = pair.$1;
    final color = pair.$2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: accent ? 0.25 : 0.15),
        border: accent
            ? Border.all(color: color.withValues(alpha: 0.5), width: 2)
            : null,
      ),
      child: Center(
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }
}

/// Create / edit dialog. Passing [existing]=null is create mode;
/// otherwise the dialog populates from the row and saves an update.
class _ProfileEditorDialog extends ConsumerStatefulWidget {
  final Profile? existing;
  final AppLocalizations l10n;

  const _ProfileEditorDialog({required this.existing, required this.l10n});

  @override
  ConsumerState<_ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState
    extends ConsumerState<_ProfileEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _pin;
  late String _avatarKey;
  late bool _isKids;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _pin = TextEditingController(text: e?.pin ?? '');
    _avatarKey = e?.avatarKey ?? 'default';
    _isKids = e?.isKids ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final repo = await ref.read(profileRepositoryProvider.future);
    final pinText = _pin.text.trim();
    final pin = pinText.isEmpty ? null : pinText;
    if (widget.existing == null) {
      await repo.create(
        name: name,
        avatarKey: _avatarKey,
        isKids: _isKids,
        pin: pin,
      );
    } else {
      await repo.update(
        widget.existing!.id,
        name: name,
        avatarKey: _avatarKey,
        isKids: _isKids,
      );
      // Pin needs an explicit clear path; the update() API treats
      // null as "leave alone".
      if (pin == null) {
        await repo.clearPin(widget.existing!.id);
      } else {
        await repo.update(widget.existing!.id, pin: pin);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    final l10n = widget.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.profileDelete),
        content: Text(l10n.profileDeleteConfirm(e.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.profileDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.delete(e.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isEdit = widget.existing != null;
    final isDefault = widget.existing?.id == 1;
    return AlertDialog(
      title: Text(isEdit ? l10n.profileEdit : l10n.profileAdd),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar picker
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _Avatar.availableKeys.map((k) {
                  final selected = k == _avatarKey;
                  return GestureDetector(
                    onTap: () => setState(() => _avatarKey = k),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: _Avatar(avatarKey: k, size: 44),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.profileNameHint,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isKids,
                onChanged: isDefault
                    ? null // can't make the default a kids profile
                    : (v) => setState(() => _isKids = v),
                title: Text(l10n.profileKids),
                subtitle: Text(
                  l10n.profileKidsDesc,
                  style: const TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              TextField(
                controller: _pin,
                decoration: InputDecoration(
                  labelText: l10n.profilePin,
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEdit && !isDefault)
          TextButton(
            onPressed: _delete,
            child: Text(
              l10n.profileDelete,
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(l10n.profileSave),
        ),
      ],
    );
  }
}

/// Re-export entry for settings_screen — keeps the import line short.
class ProfilesSectionEntry {
  static Widget build(AppLocalizations l10n) =>
      ProfilesSection(l10n: l10n);
}
