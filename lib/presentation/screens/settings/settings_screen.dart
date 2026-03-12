import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/domain/models/account_info.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/presentation/state/settings_provider.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';
import 'package:lifeostv/utils/platform_utils.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = isMobilePlatform ? -1 : 0;

  List<({IconData icon, String label})> _getSections(AppLocalizations l10n) => [
    (icon: Icons.dns_outlined, label: l10n.accounts),
    (icon: Icons.palette_outlined, label: l10n.appearance),
    (icon: Icons.play_circle_outline, label: l10n.player),
    (icon: Icons.language_outlined, label: l10n.language),
    (icon: Icons.shield_outlined, label: l10n.categories), // Content / Adult filter
    (icon: Icons.subtitles_outlined, label: l10n.subtitle), // OpenSubtitles
    (icon: Icons.storage_outlined, label: l10n.dataBackup),
    (icon: Icons.info_outline, label: l10n.about),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final sections = _getSections(l10n);

    if (isMobilePlatform) {
      return _buildMobileSettings(settings, l10n, sections, isDark);
    }

    return Scaffold(
      body: Row(
        children: [
          // Left Panel
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
              border: Border(right: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Text(
                    l10n.settings,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textDark : AppColors.textLight,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: sections.length,
                    itemBuilder: (context, index) {
                      final section = sections[index];
                      final isSelected = _selectedIndex == index;

                      return _SettingsNavItem(
                        icon: section.icon,
                        label: section.label,
                        isSelected: isSelected,
                        onTap: () => setState(() => _selectedIndex = index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right Panel
          Expanded(
            child: _buildContent(settings, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppSettings settings, AppLocalizations l10n) {
    switch (_selectedIndex) {
      case 0:
        return _AccountsSection(l10n: l10n);
      case 1:
        return _AppearanceSection(settings: settings, l10n: l10n);
      case 2:
        return _PlayerSection(settings: settings, l10n: l10n);
      case 3:
        return _LanguageSection(settings: settings, l10n: l10n);
      case 4:
        return _ContentSection(settings: settings, l10n: l10n);
      case 5:
        return _SubtitleSection(settings: settings, l10n: l10n);
      case 6:
        return _DataSection(l10n: l10n);
      case 7:
        return _AboutSection(l10n: l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMobileSettings(
    AppSettings settings,
    AppLocalizations l10n,
    List<({IconData icon, String label})> sections,
    bool isDark,
  ) {
    // If a section is selected, show it full-screen with back button
    if (_selectedIndex >= 0) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedIndex = -1),
          ),
          title: Text(
            sections[_selectedIndex.clamp(0, sections.length - 1)].label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDark : AppColors.textLight,
            ),
          ),
        ),
        body: _buildContent(settings, l10n),
      );
    }

    // Section list
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              l10n.settings,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ),
          ),
          ...List.generate(sections.length, (index) {
            final section = sections[index];
            return ListTile(
              leading: Icon(section.icon, color: AppColors.primary, size: 22),
              title: Text(
                section.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: AppColors.textTertiaryDark, size: 20),
              onTap: () => setState(() => _selectedIndex = index),
            );
          }),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsNavItem({required this.icon, required this.label, required this.isSelected, required this.onTap});

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = widget.isSelected || _isFocused;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Focus(
        onFocusChange: (f) => setState(() => _isFocused = f),
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
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : (_isFocused ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: _isFocused ? Border.all(color: AppColors.primary, width: 2) : null,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: isActive ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: isActive ? (isDark ? AppColors.textDark : AppColors.textLight) : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Accounts Section
class _AccountsSection extends ConsumerWidget {
  final AppLocalizations l10n;
  const _AccountsSection({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(savedAccountsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.accountManagement, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
        const SizedBox(height: 8),
        Text(l10n.manageAccounts, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: _SettingsActionCard(icon: Icons.dns_outlined, title: l10n.addXtreamAccount, onTap: () => context.push('/auth/xtream'))),
          const SizedBox(width: 12),
          Expanded(child: _SettingsActionCard(icon: Icons.playlist_add_outlined, title: l10n.addM3UPlaylist, onTap: () => context.push('/auth/m3u'))),
        ]),
        const SizedBox(height: 24),
        Text(l10n.savedAccounts, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? AppColors.textDark : AppColors.textLight)),
        const SizedBox(height: 12),
        accountsAsync.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                ),
                child: Column(children: [
                  Icon(Icons.account_circle_outlined, size: 48, color: AppColors.textDisabledDark),
                  const SizedBox(height: 12),
                  Text(l10n.noAccountsYet, style: TextStyle(color: AppColors.textSecondaryDark)),
                ]),
              );
            }
            return Column(children: accounts.map((account) {
              final isDefault = ref.watch(settingsProvider).defaultAccountId == account.id;
              return _AccountCard(
                account: account,
                isDefault: isDefault,
                l10n: l10n,
                isDark: isDark,
              );
            }).toList());
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('${l10n.error}: $err'),
        ),
      ],
    );
  }
}

/// Account card with expandable info section (status, expiry, connections, channel counts)
class _AccountCard extends ConsumerStatefulWidget {
  final Account account;
  final bool isDefault;
  final AppLocalizations l10n;
  final bool isDark;

  const _AccountCard({
    required this.account,
    required this.isDefault,
    required this.l10n,
    required this.isDark,
  });

  @override
  ConsumerState<_AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends ConsumerState<_AccountCard> {
  bool _expanded = false;
  AccountInfo? _info;
  bool _loadingInfo = false;

  @override
  void initState() {
    super.initState();
    // Load account info on mount for Xtream accounts
    if (widget.account.type == 'xtream') {
      _loadAccountInfo();
    }
  }

  Future<void> _loadAccountInfo() async {
    final info = await AuthRepositoryImpl.getAccountInfo(widget.account.id);
    if (mounted && info != null) {
      setState(() => _info = info);
    }
  }

  Future<void> _refreshAccountInfo() async {
    if (_loadingInfo) return;
    setState(() => _loadingInfo = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      if (authRepo is! AuthRepositoryImpl) { if (mounted) setState(() => _loadingInfo = false); return; }
      final info = await authRepo.validateAccount(widget.account);
      if (mounted) {
        setState(() {
          _info = info;
          _loadingInfo = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isDark = widget.isDark;
    final isDefault = widget.isDefault;
    final account = widget.account;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDefault ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isDefault ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Main row
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: account.type == 'xtream' ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(
                  account.type == 'xtream' ? Icons.dns : Icons.playlist_play,
                  color: isDefault ? AppColors.primary : AppColors.textSecondaryDark,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(account.name, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.textDark : AppColors.textLight))),
                    if (_info != null) ...[
                      const SizedBox(width: 8),
                      _StatusBadge(info: _info!),
                    ],
                  ]),
                  Text(account.url, style: TextStyle(fontSize: 12, color: AppColors.textSecondaryDark)),
                ])),
                if (isDefault) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(l10n.defaultLabel, style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                if (!isDefault) TextButton(onPressed: () async {
                  ref.read(settingsProvider.notifier).setDefaultAccount(account.id);
                  // Clear old data and sync new account
                  final authRepo = ref.read(authRepositoryProvider);
                  if (authRepo is AuthRepositoryImpl) {
                    await authRepo.clearUserDataForNewAccount();
                  }
                  ref.invalidate(currentAccountProvider);
                  ref.invalidate(initialSyncProvider);
                }, child: Text(l10n.setDefault)),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondaryDark),
                  tooltip: l10n.editAccount(account.name),
                  onPressed: () => context.push('/account/edit', extra: account),
                ),
                if (account.type == 'xtream')
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondaryDark,
                    size: 20,
                  ),
              ]),
            ),
          ),

          // Expanded info section
          if (_expanded && account.type == 'xtream')
            _buildInfoSection(l10n, isDark),
        ],
      ),
    );
  }

  Widget _buildInfoSection(AppLocalizations l10n, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 12),

          if (_info != null) ...[
            // Info grid
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                // Expiration
                if (_info!.expiryDate != null)
                  _InfoChip(
                    icon: Icons.calendar_today,
                    label: l10n.expiration,
                    value: '${DateFormat('dd.MM.yyyy').format(_info!.expiryDate!)} (${l10n.daysRemaining(_info!.remainingDays ?? 0)})',
                    color: (_info!.remainingDays ?? 0) < 7 ? Colors.orange : AppColors.textSecondaryDark,
                  ),
                // Connections
                _InfoChip(
                  icon: Icons.people_outline,
                  label: l10n.connections,
                  value: '${_info!.activeConnections} / ${_info!.maxConnections}',
                ),
                // Created
                if (_info!.createdAt != null)
                  _InfoChip(
                    icon: Icons.access_time,
                    label: l10n.createdAt,
                    value: DateFormat('dd.MM.yyyy').format(_info!.createdAt!),
                  ),
                // Trial
                if (_info!.isTrial)
                  _InfoChip(
                    icon: Icons.star_outline,
                    label: 'Trial',
                    value: l10n.yes,
                    color: Colors.amber,
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text(
              l10n.accountInfoLoadFailed,
              style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],

          // Refresh button
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loadingInfo ? null : _refreshAccountInfo,
              icon: _loadingInfo
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_loadingInfo ? l10n.checking : l10n.checkConnection),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AccountInfo info;
  const _StatusBadge({required this.info});

  @override
  Widget build(BuildContext context) {
    final isActive = info.isActive;
    final color = isActive ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        info.status,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _InfoChip({required this.icon, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppColors.textSecondaryDark),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12)),
        Text(value, style: TextStyle(color: color ?? AppColors.textDark, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _SettingsActionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _SettingsActionCard({required this.icon, required this.title, required this.onTap});
  @override
  State<_SettingsActionCard> createState() => _SettingsActionCardState();
}

class _SettingsActionCardState extends State<_SettingsActionCard> {
  bool _isFocused = false;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
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
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _isFocused ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.borderLight), width: _isFocused ? 2 : 1),
          ),
          child: Column(children: [
            Icon(widget.icon, size: 32, color: _isFocused ? AppColors.primary : AppColors.textSecondaryDark),
            const SizedBox(height: 10),
            Text(widget.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppColors.textDark : AppColors.textLight), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

// Appearance Section
class _AppearanceSection extends ConsumerWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _AppearanceSection({required this.settings, required this.l10n});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.appearance, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 24),
      SwitchListTile(
        title: Text(l10n.darkMode, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.darkModeDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.themeMode == AppThemeMode.dark,
        onChanged: (val) => ref.read(settingsProvider.notifier).setTheme(val ? AppThemeMode.dark : AppThemeMode.light),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    ]);
  }
}

// Player Section
class _PlayerSection extends ConsumerWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _PlayerSection({required this.settings, required this.l10n});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.playerSettings, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 24),
      SwitchListTile(
        title: Text(l10n.hardwareAcceleration, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.hardwareAccelerationDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.hardwareAcceleration,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(hardwareAcceleration: val)),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      // Stream Quality dropdown
      ListTile(
        leading: Icon(Icons.hd_outlined, color: AppColors.primary),
        title: Text(l10n.streamQuality, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.streamQualityDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        trailing: DropdownButton<StreamQuality>(
          value: settings.streamQuality,
          dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceLight,
          underline: const SizedBox.shrink(),
          style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight, fontSize: 13),
          items: [
            DropdownMenuItem(value: StreamQuality.auto, child: Text(l10n.qualityAuto)),
            DropdownMenuItem(value: StreamQuality.high, child: Text(l10n.qualityHigh)),
            DropdownMenuItem(value: StreamQuality.medium, child: Text(l10n.qualityMedium)),
            DropdownMenuItem(value: StreamQuality.low, child: Text(l10n.qualityLow)),
          ],
          onChanged: (val) {
            if (val != null) {
              ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(streamQuality: val));
            }
          },
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      ListTile(
        title: Text(l10n.bufferDuration, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text('${settings.bufferDuration} ${l10n.seconds}', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: Icon(Icons.remove_circle_outline, color: AppColors.textSecondaryDark),
            onPressed: settings.bufferDuration > 5 ? () => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(bufferDuration: settings.bufferDuration - 5)) : null),
          IconButton(icon: Icon(Icons.add_circle_outline, color: AppColors.textSecondaryDark),
            onPressed: settings.bufferDuration < 60 ? () => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(bufferDuration: settings.bufferDuration + 5)) : null),
        ]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        title: Text(l10n.nextEpisode, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.continueWatching, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.autoNextEpisode,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(autoNextEpisode: val)),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    ]);
  }
}

// Language Section
class _LanguageSection extends ConsumerWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _LanguageSection({required this.settings, required this.l10n});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languages = [
      (value: AppLanguage.system, label: l10n.systemDefault, icon: Icons.settings_suggest),
      (value: AppLanguage.en, label: 'English', icon: Icons.language),
      (value: AppLanguage.tr, label: 'Türkçe', icon: Icons.language),
      (value: AppLanguage.de, label: 'Deutsch', icon: Icons.language),
      (value: AppLanguage.fr, label: 'Français', icon: Icons.language),
      (value: AppLanguage.es, label: 'Español', icon: Icons.language),
      (value: AppLanguage.ar, label: 'العربية', icon: Icons.language),
      (value: AppLanguage.ru, label: 'Русский', icon: Icons.language),
      (value: AppLanguage.ku, label: 'Kurdî', icon: Icons.language),
    ];
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.language, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 8),
      Text(l10n.selectLanguage, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
      const SizedBox(height: 24),
      ...languages.map((lang) {
        final isSelected = settings.language == lang.value;
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: _FocusableListTile(
          leading: Icon(lang.icon, color: isSelected ? AppColors.primary : AppColors.textSecondaryDark),
          title: Text(lang.label, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
          trailing: isSelected ? Icon(Icons.check_circle, color: AppColors.primary) : Icon(Icons.radio_button_unchecked, color: isDark ? AppColors.borderDark : AppColors.borderLight),
          selected: isSelected,
          selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
          tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderColor: isSelected ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.borderLight),
          onTap: () {
            ref.read(settingsProvider.notifier).setLanguage(lang.value);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.languageSet(lang.label)), duration: const Duration(seconds: 2)),
            );
          },
        ));
      }),
    ]);
  }
}

// Focusable ListTile for TV remote support
class _FocusableListTile extends StatefulWidget {
  final Widget? leading;
  final Widget title;
  final Widget? trailing;
  final bool selected;
  final Color? selectedTileColor;
  final Color? tileColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _FocusableListTile({
    this.leading,
    required this.title,
    this.trailing,
    this.selected = false,
    this.selectedTileColor,
    this.tileColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  State<_FocusableListTile> createState() => _FocusableListTileState();
}

class _FocusableListTileState extends State<_FocusableListTile> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListTile(
        leading: widget.leading,
        title: widget.title,
        trailing: widget.trailing,
        selected: widget.selected,
        selectedTileColor: widget.selectedTileColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: _isFocused ? AppColors.primary : widget.borderColor,
            width: _isFocused ? 2 : 1,
          ),
        ),
        tileColor: _isFocused
            ? AppColors.primary.withValues(alpha: 0.12)
            : widget.tileColor,
        onTap: widget.onTap,
      ),
    );
  }
}

// Content Management Section (Adult filter, continue watching)
class _ContentSection extends ConsumerWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _ContentSection({required this.settings, required this.l10n});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.categories, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 24),
      SwitchListTile(
        secondary: Icon(Icons.shield_outlined, color: AppColors.primary),
        title: Text(l10n.live, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text('18+ / XXX', style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.autoHideAdult,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(autoHideAdult: val)),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        secondary: Icon(Icons.history, color: AppColors.primary),
        title: Text(l10n.continueWatching, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        value: settings.continueWatchingEnabled,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(continueWatchingEnabled: val)),
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    ]);
  }
}

// Subtitle / OpenSubtitles Section
class _SubtitleSection extends ConsumerStatefulWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _SubtitleSection({required this.settings, required this.l10n});

  @override
  ConsumerState<_SubtitleSection> createState() => _SubtitleSectionState();
}

class _SubtitleSectionState extends ConsumerState<_SubtitleSection> {
  late final TextEditingController _apiKeyController;

  static const _subtitleLanguages = <String, String>{
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'ar': 'العربية',
    'ru': 'Русский',
    'ku': 'Kurdî',
    'pt-br': 'Português (BR)',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'ro': 'Română',
    'el': 'Ελληνικά',
    'hu': 'Magyar',
    'cs': 'Čeština',
    'bg': 'Български',
    'hr': 'Hrvatski',
    'sv': 'Svenska',
    'no': 'Norsk',
    'da': 'Dansk',
    'fi': 'Suomi',
    'ja': '日本語',
    'ko': '한국어',
    'zh-cn': '中文 (简体)',
    'zh-tw': '中文 (繁體)',
    'hi': 'हिन्दी',
    'fa': 'فارسی',
    'he': 'עברית',
  };

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.settings.opensubtitlesApiKey ?? '');
  }

  @override
  void didUpdateWidget(covariant _SubtitleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.opensubtitlesApiKey != widget.settings.opensubtitlesApiKey) {
      _apiKeyController.text = widget.settings.opensubtitlesApiKey ?? '';
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _saveApiKey() {
    final key = _apiKeyController.text.trim();
    ref.read(settingsProvider.notifier).updateSettings(
      widget.settings.copyWith(opensubtitlesApiKey: key.isEmpty ? null : key),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(key.isEmpty ? widget.l10n.apiKeyCleared : widget.l10n.apiKeySaved), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final settings = widget.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.subtitleSettings, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 8),
      Text(l10n.subtitleSearchInfo, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
      const SizedBox(height: 24),

      // API Key input
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.key_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(l10n.opensubtitlesApiKey, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.textDark : AppColors.textLight)),
          ]),
          const SizedBox(height: 4),
          Text(l10n.opensubtitlesApiKeyDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  hintText: l10n.apiKeyHint,
                  hintStyle: TextStyle(color: AppColors.textDisabledDark),
                  filled: true,
                  fillColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.primary, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight, fontSize: 13),
                onSubmitted: (_) => _saveApiKey(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saveApiKey,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(l10n.save),
            ),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Preferred subtitle language
      ListTile(
        leading: Icon(Icons.translate, color: AppColors.primary),
        title: Text(l10n.preferredSubtitleLanguage, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.preferredSubtitleLanguageDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        trailing: DropdownButton<String>(
          value: _subtitleLanguages.containsKey(settings.subtitlePreferredLanguage)
              ? settings.subtitlePreferredLanguage
              : 'tr',
          dropdownColor: isDark ? AppColors.surfaceElevatedDark : AppColors.surfaceLight,
          underline: const SizedBox.shrink(),
          style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight, fontSize: 13),
          items: _subtitleLanguages.entries.map((e) =>
            DropdownMenuItem(value: e.key, child: Text(e.value)),
          ).toList(),
          onChanged: (val) {
            if (val != null) {
              ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(subtitlePreferredLanguage: val),
              );
            }
          },
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),

      const SizedBox(height: 28),
      Text(l10n.subtitleAppearance, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 16),

      // Font size slider
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.format_size, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(l10n.subtitleFontSize, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.textDark : AppColors.textLight)),
            const Spacer(),
            Text('${settings.subtitleFontSize}', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          Slider(
            value: settings.subtitleFontSize.toDouble(),
            min: 16,
            max: 72,
            divisions: 28,
            activeColor: AppColors.primary,
            label: '${settings.subtitleFontSize}',
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(subtitleFontSize: val.round()),
              );
            },
          ),
          // Preview
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Altyazı Örneği',
                style: TextStyle(
                  color: _hexToColor(settings.subtitleColor),
                  fontSize: settings.subtitleFontSize.toDouble().clamp(12, 36),
                  fontWeight: settings.subtitleBold ? FontWeight.bold : FontWeight.normal,
                  backgroundColor: settings.subtitleBackgroundEnabled
                      ? Colors.black54
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ]),
      ),

      const SizedBox(height: 16),

      // Color picker
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.palette_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(l10n.subtitleColor, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? AppColors.textDark : AppColors.textLight)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _subtitleColors.entries.map((e) {
              final isSelected = settings.subtitleColor.toUpperCase() == e.key.toUpperCase();
              return GestureDetector(
                onTap: () {
                  ref.read(settingsProvider.notifier).updateSettings(
                    settings.copyWith(subtitleColor: e.key),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 8)]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(Icons.check, color: e.value.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
        ]),
      ),

      const SizedBox(height: 16),

      // Bold toggle
      SwitchListTile(
        secondary: Icon(Icons.format_bold, color: AppColors.primary),
        title: Text(l10n.subtitleBold, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        value: settings.subtitleBold,
        activeColor: AppColors.primary,
        onChanged: (val) {
          ref.read(settingsProvider.notifier).updateSettings(
            settings.copyWith(subtitleBold: val),
          );
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),

      const SizedBox(height: 8),

      // Background toggle
      SwitchListTile(
        secondary: Icon(Icons.rectangle_outlined, color: AppColors.primary),
        title: Text(l10n.subtitleBackground, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.subtitleBackgroundDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.subtitleBackgroundEnabled,
        activeColor: AppColors.primary,
        onChanged: (val) {
          ref.read(settingsProvider.notifier).updateSettings(
            settings.copyWith(subtitleBackgroundEnabled: val),
          );
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    ]);
  }

  static const _subtitleColors = <String, Color>{
    '#FFFFFF': Color(0xFFFFFFFF), // White
    '#FFFF00': Color(0xFFFFFF00), // Yellow
    '#00FF00': Color(0xFF00FF00), // Green
    '#00FFFF': Color(0xFF00FFFF), // Cyan
    '#FF4444': Color(0xFFFF4444), // Red
    '#4488FF': Color(0xFF4488FF), // Blue
    '#FF8800': Color(0xFFFF8800), // Orange
    '#FF44FF': Color(0xFFFF44FF), // Pink
  };

  static Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}

// Data Section
class _DataSection extends StatelessWidget {
  final AppLocalizations l10n;
  const _DataSection({required this.l10n});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.dataBackup, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppColors.textDark : AppColors.textLight)),
      const SizedBox(height: 24),
      ListTile(
        leading: Icon(Icons.delete_outline, color: AppColors.primary),
        title: Text(l10n.clearCache, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.clearCacheDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        onTap: () {
          ApiCache.instance.clear();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.cacheClearedMsg)));
        },
      ),
    ]);
  }
}

// About Section
class _AboutSection extends StatelessWidget {
  final AppLocalizations l10n;
  const _AboutSection({required this.l10n});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final surfaceColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderDark : AppColors.borderLight;

    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(l10n.about, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
      const SizedBox(height: 24),

      // App info card
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
            child: const Text('TV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24)),
          ),
          const SizedBox(height: 12),
          Text('LifeOS TV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
          const SizedBox(height: 4),
          Text('${l10n.version} 1.0.0', style: TextStyle(color: secondaryColor)),
          const SizedBox(height: 16),
          Text(l10n.aboutDescription, style: TextStyle(color: secondaryColor, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
        ]),
      ),
      const SizedBox(height: 16),

      // Developer info card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.developerInfo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.person_outline, l10n.developer, 'Erkan ÖZ', textColor, secondaryColor),
          Divider(color: borderColor, height: 24),
          _buildInfoRow(Icons.email_outlined, 'E-mail', 'erkanoz07@gmail.com', textColor, secondaryColor),
          Divider(color: borderColor, height: 24),
          _buildInfoRow(Icons.language, l10n.website, 'lifeos.com.tr', textColor, secondaryColor),
          Divider(color: borderColor, height: 24),
          _buildInfoRow(Icons.copyright, l10n.license, l10n.allRightsReserved, textColor, secondaryColor),
          const SizedBox(height: 8),
          Text(l10n.copyrightNotice, style: TextStyle(color: secondaryColor, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 16),

      // Legal disclaimer card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gavel, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(l10n.legalDisclaimer, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          ]),
          const SizedBox(height: 12),
          Text(l10n.disclaimerText, style: TextStyle(color: secondaryColor, fontSize: 13, height: 1.6)),
        ]),
      ),
      const SizedBox(height: 16),

      // License card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(l10n.license, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
          ]),
          const SizedBox(height: 12),
          Text(l10n.licenseText, style: TextStyle(color: secondaryColor, fontSize: 13, height: 1.6)),
        ]),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color textColor, Color secondaryColor) {
    return Row(children: [
      Icon(icon, size: 18, color: secondaryColor),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: secondaryColor, fontSize: 13)),
      const Spacer(),
      Text(value, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}
