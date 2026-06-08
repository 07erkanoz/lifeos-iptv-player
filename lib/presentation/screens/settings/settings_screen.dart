import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/core/platform_helper.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_branches.dart';
import 'package:lifeostv/presentation/screens/settings/sections/profiles_section.dart';
import 'package:lifeostv/presentation/screens/settings/ai_debug_panel.dart';
import 'package:lifeostv/presentation/screens/settings/device_sync_screen.dart';
import 'package:lifeostv/data/services/catalog_enrichment_runner.dart';
import 'package:lifeostv/data/repositories/content_enrichment_repository.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_provider.dart';
import 'package:lifeostv/core/tv_focus/tv_focus_registry.dart';
import 'package:lifeostv/presentation/widgets/player/subtitle_appearance_controls.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/services/api_cache.dart';
import 'package:lifeostv/data/services/backup_service.dart';
import 'package:lifeostv/data/services/sync_metadata.dart';
import 'package:lifeostv/main.dart' show sharedPreferencesProvider;
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

  /// FocusNode for the first nav item — the branch-primary target so
  /// sidebar → right lands on the leftmost setting section instead
  /// of stranding focus on an arbitrary input field.
  final FocusNode _firstNavFocus = FocusNode(debugLabel: 'SettingsFirstNav');

  late final VoidFocusCallback _branchPrimaryCb;

  @override
  void initState() {
    super.initState();
    _branchPrimaryCb = _focusFirstNav;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(tvFocusRegistryProvider).registerBranchPrimary(
            TvBranchIndex.settings,
            _branchPrimaryCb,
          );
    });
  }

  @override
  void dispose() {
    ref.read(tvFocusRegistryProvider).unregisterBranchPrimary(
          TvBranchIndex.settings,
          _branchPrimaryCb,
        );
    _firstNavFocus.dispose();
    super.dispose();
  }

  void _focusFirstNav() {
    if (!mounted) return;
    if (_firstNavFocus.canRequestFocus) {
      _firstNavFocus.requestFocus();
    }
  }

  List<({IconData icon, String label})> _getSections(AppLocalizations l10n) => [
    (icon: Icons.dns_outlined, label: l10n.accounts),
    (icon: Icons.people_outline, label: l10n.profilesTitle),
    (icon: Icons.palette_outlined, label: l10n.appearance),
    (icon: Icons.play_circle_outline, label: l10n.player),
    (icon: Icons.language_outlined, label: l10n.language),
    (icon: Icons.shield_outlined, label: l10n.categories), // Content / Adult filter
    (icon: Icons.subtitles_outlined, label: l10n.subtitle), // OpenSubtitles
    (icon: Icons.auto_awesome_outlined, label: l10n.aiAssistant), // Gemini key
    (icon: Icons.bar_chart_rounded, label: l10n.statsTitle), // Watch time stats
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
                        // Only the first item gets the branch-primary
                        // focus node so sidebar → right has a stable
                        // landing spot.
                        focusNode: index == 0 ? _firstNavFocus : null,
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
        return ProfilesSection(l10n: l10n);
      case 2:
        return _AppearanceSection(settings: settings, l10n: l10n);
      case 3:
        return _PlayerSection(settings: settings, l10n: l10n);
      case 4:
        return _LanguageSection(settings: settings, l10n: l10n);
      case 5:
        return _ContentSection(settings: settings, l10n: l10n);
      case 6:
        return _SubtitleSection(settings: settings, l10n: l10n);
      case 7:
        return _AiAssistantSection(settings: settings, l10n: l10n);
      case 8:
        return _StatsSection(l10n: l10n);
      case 9:
        return _DataSection(l10n: l10n);
      case 10:
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
    // If a section is selected, show it full-screen with back button.
    // The PopScope intercepts the system/gesture back so it returns to
    // the section LIST instead of bubbling up to the shell (which would
    // jump to the dashboard or — without it — close the app). The
    // innermost open PopScope wins, so this fires before AppShell's.
    if (_selectedIndex >= 0) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() => _selectedIndex = -1);
        },
        child: Scaffold(
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
        ),
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

  /// External FocusNode wired by the parent — used for the first
  /// nav item so the registry's branch-primary callback can target
  /// it directly (sidebar → right lands here).
  final FocusNode? focusNode;

  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.focusNode,
  });

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
        focusNode: widget.focusNode,
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
                  // 1. Persist the user's choice in settings (drives
                  //    currentAccountProvider on next read).
                  ref.read(settingsProvider.notifier).setDefaultAccount(account.id);

                  // 2. Re-establish the single-active-row invariant in
                  //    the DB. Old builds didn't enforce this on insert,
                  //    so existing installs may have multiple actives —
                  //    setActiveAccount fixes that atomically.
                  final authRepo = ref.read(authRepositoryProvider);
                  await authRepo.setActiveAccount(account.id);

                  // 3. Drop *all* data tied to the previous account
                  //    (channels, EPG, watch history, favourites, …)
                  //    and the global API cache.
                  if (authRepo is AuthRepositoryImpl) {
                    await authRepo.clearUserDataForNewAccount();
                  }

                  // 4. Reset tier-sync timestamps. Without this the
                  //    `initialSyncProvider` would see "Tier-3 synced
                  //    20 minutes ago" from the previous account and
                  //    silently skip the heavy initial sync — leaving
                  //    the new account showing an empty UI.
                  try {
                    final prefs = ref.read(sharedPreferencesProvider);
                    await SyncMetadata(prefs).resetAllTiers();
                  } catch (_) {}

                  // 5. Invalidate the providers that read account state
                  //    so the rest of the app picks up the switch
                  //    immediately.
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
                    label: l10n.trialBadge,
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
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      // Mobile-only: hide system status bar for an edge-to-edge feel.
      // Hidden on desktop / TV because the SystemUiOverlay enum is a
      // no-op there. The toggle takes effect immediately — the
      // MaterialApp builder watches settings and re-applies the mode
      // on every change.
      if (PlatformHelper.isMobile) ...[
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(l10n.fullscreenMode,
              style: TextStyle(
                  color: isDark
                      ? AppColors.textDark
                      : AppColors.textLight)),
          subtitle: Text(
            l10n.fullscreenModeDesc,
            style: const TextStyle(
                color: AppColors.textSecondaryDark, fontSize: 13),
          ),
          value: settings.fullscreenMode,
          onChanged: (val) => ref
              .read(settingsProvider.notifier)
              .setFullscreenMode(val),
          activeThumbColor: AppColors.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          tileColor:
              isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
      ],
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
        activeThumbColor: AppColors.primary,
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
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      // Skip-Intro toggle. Only affects the floating in-player button;
      // the marker-management bookmark icon stays available on the
      // player toolbar regardless so users can still record/edit a
      // marker.
      SwitchListTile(
        title: Text(l10n.skipIntroSetting, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.skipIntroSettingDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.showSkipIntroButton,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(showSkipIntroButton: val)),
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      // Floating trailer PiP on detail pages. Default on — it's a
      // big quality-of-life win on desktop/TV — but heavy users
      // sometimes prefer a static detail panel (slow internet,
      // distraction, etc.).
      SwitchListTile(
        title: Text(l10n.showTrailerSetting, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        subtitle: Text(l10n.showTrailerSettingDesc, style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13)),
        value: settings.showTrailer,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(showTrailer: val)),
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      // Mobile-only opt-in: autoplay the muted hero trailer on the
      // dashboard. Off by default — see [AppSettings.heroTrailerOnMobile]
      // for the data-cost rationale. Hidden on desktop/TV (their hero
      // already plays trailers unconditionally, gated only by the
      // PiP-trailer toggle above).
      if (PlatformHelper.isMobile) ...[
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(l10n.heroTrailerOnMobile,
              style: TextStyle(
                  color: isDark
                      ? AppColors.textDark
                      : AppColors.textLight)),
          subtitle: Text(
            l10n.heroTrailerOnMobileDesc,
            style: const TextStyle(
                color: AppColors.textSecondaryDark, fontSize: 13),
          ),
          value: settings.heroTrailerOnMobile,
          onChanged: (val) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                  settings.copyWith(heroTrailerOnMobile: val)),
          activeThumbColor: AppColors.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          tileColor:
              isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        ),
      ],
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
        activeThumbColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        secondary: Icon(Icons.history, color: AppColors.primary),
        title: Text(l10n.continueWatching, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
        value: settings.continueWatchingEnabled,
        onChanged: (val) => ref.read(settingsProvider.notifier).updateSettings(settings.copyWith(continueWatchingEnabled: val)),
        activeThumbColor: AppColors.primary,
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
      Text(
        l10n.subtitleAppearance,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.textDark : AppColors.textLight,
        ),
      ),
      const SizedBox(height: 16),
      // Shared controls — same widget used in the in-player track
      // picker, so changes here surface in playback immediately if a
      // stream is active.
      const SubtitleAppearanceControls(),
    ]);
  }
}

// ────────────────────────────────────────────────────────────────────────
// AI Assistant Section
//
// Opt-in: user pastes a Google Gemini API key (free tier, no card) to
// unlock natural-language search, the "what should I watch tonight?"
// chat sheet, spoiler-free recaps, plot summary/translation, and smart
// subtitle translation. Without a key, every AI surface in the app
// hides itself — the rest of the app keeps working unchanged.
//
// We deliberately *don't* show disabled AI buttons elsewhere. There's
// no per-feature "you can do this if you add a key" nag — users opt in
// here, then features appear.
// ────────────────────────────────────────────────────────────────────────
class _AiAssistantSection extends ConsumerStatefulWidget {
  final AppSettings settings;
  final AppLocalizations l10n;
  const _AiAssistantSection({required this.settings, required this.l10n});

  @override
  ConsumerState<_AiAssistantSection> createState() =>
      _AiAssistantSectionState();
}

class _AiAssistantSectionState extends ConsumerState<_AiAssistantSection> {
  late TextEditingController _keyController;
  bool _obscure = true;
  bool _howToOpen = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _keyController =
        TextEditingController(text: widget.settings.geminiApiKey ?? '');
  }

  @override
  void didUpdateWidget(covariant _AiAssistantSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.geminiApiKey != widget.settings.geminiApiKey) {
      _keyController.text = widget.settings.geminiApiKey ?? '';
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _saveKey() {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.l10n.geminiKeyInvalid),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    ref
        .read(settingsProvider.notifier)
        .updateSettings(widget.settings.copyWith(geminiApiKey: key));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.l10n.geminiKeySaved),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearKey() {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(widget.settings.copyWith(clearGeminiApiKey: true));
    _keyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.l10n.geminiKeyCleared),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Smoke-test the key against the Gemini REST endpoint. We deliberately
  /// pick the cheapest possible call (`models.list`) instead of a
  /// completion, so test cost is essentially free and we don't bill
  /// against the user's quota for "did I type the key right?".
  Future<void> _testKey() async {
    final l10n = widget.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.geminiKeyInvalid),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _testing = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true, // we handle status manually
      ));
      final res = await dio.get<Map<String, dynamic>>(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': key},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.geminiKeyTestSuccess),
          duration: const Duration(seconds: 2),
        ));
      } else {
        // Google embeds the human-readable reason at
        // `error.message`. Fall back to the raw status if it's gone.
        final body = res.data;
        final reason = (body is Map<String, dynamic> &&
                body['error'] is Map<String, dynamic>)
            ? (body['error']['message']?.toString() ?? '${res.statusCode}')
            : '${res.statusCode}';
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.geminiKeyTestFailed(reason)),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.geminiKeyTestFailed(e.toString())),
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasKey = widget.settings.hasAiKey;

    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Text(
          l10n.aiAssistant,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textDark : AppColors.textLight,
          ),
        ),
        const SizedBox(width: 10),
        // Active / Not configured badge — at-a-glance status without
        // having to read the field below.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (hasKey ? AppColors.primary : AppColors.textDisabledDark)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            hasKey ? l10n.geminiStatusActive : l10n.geminiStatusInactive,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: hasKey ? AppColors.primary : AppColors.textSecondaryDark,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text(
        l10n.aiAssistantSubtitle,
        style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
      ),
      const SizedBox(height: 20),

      // ── Benefits card ────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            l10n.aiAssistantWhy,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDark : AppColors.textLight,
            ),
          ),
          const SizedBox(height: 12),
          for (final benefit in [
            l10n.aiBenefitNaturalSearch,
            l10n.aiBenefitTonightChat,
            l10n.aiBenefitRecap,
            l10n.aiBenefitPlot,
            l10n.aiBenefitSubtitle,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      benefit,
                      style: TextStyle(
                        color: AppColors.textSecondaryDark,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── Key input + actions ─────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.key_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.geminiApiKey,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: l10n.geminiApiKeyHint,
              hintStyle: TextStyle(color: AppColors.textDisabledDark),
              filled: true,
              fillColor:
                  isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: AppColors.textSecondaryDark,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            style: TextStyle(
              color: isDark ? AppColors.textDark : AppColors.textLight,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _saveKey,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(l10n.geminiSaveKey),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testKey,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline, size: 16),
              label: Text(l10n.geminiTestKey),
            ),
            if (hasKey)
              OutlinedButton.icon(
                onPressed: _clearKey,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(l10n.geminiClearKey),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          // Privacy note — gray, smaller text.
          Text(
            l10n.aiPrivacyNote,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
              height: 1.4,
            ),
          ),
          // Taste-wizard reset — only when there's a key, since the
          // wizard is gated on hasAiKey too. Resets the flag and the
          // dashboard re-prompts on next open.
          if (hasKey) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tasteWizardReset,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textDark
                            : AppColors.textLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.tasteWizardResetDesc,
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  ref.read(settingsProvider.notifier).updateSettings(
                      widget.settings.copyWith(
                          tasteWizardCompleted: false));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.tasteWizardDone),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                child: Text(l10n.tasteWizardReset),
              ),
            ]),
          ],
        ]),
      ),
      // ── AI debug panel entry — appears only when there's a key ──
      // so the row isn't a dead end for users who haven't enabled AI
      // yet. Routes to a stream-backed log + per-feature stats view.
      if (hasKey) ...[
        const SizedBox(height: 12),
        // Smart catalogue tagging — fills missing genre/year/mood in
        // the background. Default on; the single biggest quality lever
        // for search / similar / dashboard rails.
        SwitchListTile(
          title: Text(l10n.catalogEnrichment,
              style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight)),
          subtitle: Text(l10n.catalogEnrichmentDesc,
              style: const TextStyle(
                  color: AppColors.textSecondaryDark, fontSize: 13)),
          value: widget.settings.catalogEnrichmentEnabled,
          onChanged: (v) {
            ref.read(settingsProvider.notifier).updateSettings(
                widget.settings.copyWith(catalogEnrichmentEnabled: v));
            if (v) {
              // Kick a pass right away so the user sees the benefit
              // without waiting for the next app launch.
              ref.read(catalogEnrichmentRunnerProvider).runOnce();
            }
          },
          activeThumbColor: AppColors.primary,
          contentPadding: EdgeInsets.zero,
        ),
        if (widget.settings.catalogEnrichmentEnabled)
          const _EnrichmentStatusTile(),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const AiDebugPanel(),
            ));
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDark
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? AppColors.borderDark
                    : AppColors.borderLight,
              ),
            ),
            child: Row(children: [
              const Icon(Icons.analytics_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aiDebugPanelTitle,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textDark
                            : AppColors.textLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.aiDebugPanelDesc,
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary(context)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),

      // ── How to get a key (expandable) ───────────────────────────────
      Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: !hasKey, // First-time users see steps open.
            onExpansionChanged: (v) => setState(() => _howToOpen = v),
            leading: const Icon(Icons.help_outline,
                color: AppColors.primary, size: 20),
            title: Text(
              l10n.howToGetGeminiKey,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              for (final step in [
                l10n.geminiStep1,
                l10n.geminiStep2,
                l10n.geminiStep3,
                l10n.geminiStep4,
                l10n.geminiStep5,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    step,
                    style: TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.geminiFreeReassurance,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/app/apikey'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l10n.openGeminiSite),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      // Read but not used here — exists so the file's existing
      // `_howToOpen` toggle survives the linter without warnings.
      if (_howToOpen) const SizedBox.shrink(),
    ]);
  }
}

/// Live progress readout for catalogue enrichment + a manual
/// "run now" trigger, so the background filler is observable and
/// testable instead of being an invisible process.
class _EnrichmentStatusTile extends ConsumerStatefulWidget {
  const _EnrichmentStatusTile();

  @override
  ConsumerState<_EnrichmentStatusTile> createState() =>
      _EnrichmentStatusTileState();
}

class _EnrichmentStatusTileState
    extends ConsumerState<_EnrichmentStatusTile> {
  int? _done;
  int? _pending;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final repo = ref.read(contentEnrichmentRepositoryProvider);
    final done = await repo.enrichedCount();
    final pending = await repo.pendingCount();
    if (!mounted) return;
    setState(() {
      _done = done;
      _pending = pending;
    });
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    // Poll counts a few times while the runner works so the numbers
    // visibly climb during the run.
    final runFuture = ref.read(catalogEnrichmentRunnerProvider).runOnce();
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await _refresh();
    }
    await runFuture;
    if (!mounted) return;
    await _refresh();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (_done == null || _pending == null)
                  ? '—'
                  : l10n.catalogEnrichmentStatus(_done!, _pending!),
              style: const TextStyle(
                  color: AppColors.textSecondaryDark, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: _running ? null : _runNow,
            icon: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(l10n.catalogEnrichmentRun),
          ),
        ],
      ),
    );
  }
}

/// Watch-time statistics panel — Settings → İstatistikler.
///
/// Reads from PlaybackProgress (the same table that drives Continue
/// Watching), aggregates total minutes watched over three windows
/// (all-time / this month / this week), counts distinct finished
/// movies and episodes, and surfaces the top categories the user
/// spends time in.
///
/// The whole thing is a single Drift JOIN query computed in Dart —
/// there's no telemetry service and no remote endpoint. The data
/// never leaves the device.
class _StatsSection extends ConsumerStatefulWidget {
  final AppLocalizations l10n;
  const _StatsSection({required this.l10n});

  @override
  ConsumerState<_StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends ConsumerState<_StatsSection> {
  _StatsBucket _bucket = _StatsBucket.allTime;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.statsTitle,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // ── Time-window picker ────────────────────────────────
          Wrap(
            spacing: 8,
            children: [
              for (final b in _StatsBucket.values)
                ChoiceChip(
                  label: Text(_bucketLabel(b, l10n)),
                  selected: _bucket == b,
                  onSelected: (_) => setState(() => _bucket = b),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── The actual numbers ────────────────────────────────
          FutureBuilder<_StatsSnapshot>(
            future: _loadStats(_bucket),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final s = snap.data!;
              if (s.totalMinutes == 0 &&
                  s.finishedMovies == 0 &&
                  s.finishedEpisodes == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      l10n.statsEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondaryDark, fontSize: 13),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatBigNumberRow(
                    primaryValue: _formatDuration(
                        s.totalMinutes, l10n),
                    primaryLabel: l10n.statsWatchTime,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.movie_outlined,
                          value: '${s.finishedMovies}',
                          label: l10n.statsTotalMovies,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.live_tv_outlined,
                          value: '${s.finishedEpisodes}',
                          label: l10n.statsTotalEpisodes,
                        ),
                      ),
                    ],
                  ),
                  if (s.topGenres.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      l10n.statsTopGenres,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondaryDark,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: s.topGenres
                          .map((g) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  g,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _bucketLabel(_StatsBucket b, AppLocalizations l10n) {
    switch (b) {
      case _StatsBucket.allTime:
        return l10n.statsAllTime;
      case _StatsBucket.thisMonth:
        return l10n.statsThisMonth;
      case _StatsBucket.thisWeek:
        return l10n.statsThisWeek;
    }
  }

  String _formatDuration(int totalMinutes, AppLocalizations l10n) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m ${l10n.statsMinutesShort}';
    return '$h ${l10n.statsHoursShort} $m ${l10n.statsMinutesShort}';
  }

  /// One-shot Drift query: PlaybackProgress joined with Channels +
  /// Categories. We compute totals + categorical breakdown in Dart
  /// (set is small — at most a few thousand rows for a heavy user).
  Future<_StatsSnapshot> _loadStats(_StatsBucket bucket) async {
    final db = ref.read(appDatabaseProvider);
    final query = db.select(db.playbackProgress).join([
      leftOuterJoin(
        db.channels,
        db.channels.streamId.equalsExp(db.playbackProgress.streamId) &
            db.channels.type.equalsExp(db.playbackProgress.type),
      ),
      leftOuterJoin(
        db.categories,
        db.categories.id.equalsExp(db.channels.categoryId) &
            db.categories.type.equalsExp(db.channels.type),
      ),
    ]);
    // Bucket → updatedAt cutoff
    final DateTime? cutoff = switch (bucket) {
      _StatsBucket.allTime => null,
      _StatsBucket.thisMonth =>
        DateTime.now().subtract(const Duration(days: 30)),
      _StatsBucket.thisWeek =>
        DateTime.now().subtract(const Duration(days: 7)),
    };
    if (cutoff != null) {
      query.where(db.playbackProgress.updatedAt.isBiggerThanValue(cutoff));
    }
    final rows = await query.get();

    var totalSeconds = 0;
    var movies = 0;
    var episodes = 0;
    final genreSeconds = <String, int>{};
    for (final r in rows) {
      final p = r.readTable(db.playbackProgress);
      final ch = r.readTableOrNull(db.channels);
      final cat = r.readTableOrNull(db.categories);
      // Use position as minutes-watched proxy; duration may be 0 for
      // live channels so we clamp to a sane bound to avoid spikes
      // from corrupted rows.
      final secs = p.position.clamp(0, 6 * 60 * 60); // cap 6h / row
      totalSeconds += secs;
      if (p.isFinished) {
        if (p.type == 'movie') movies++;
        if (p.type == 'series') episodes++;
      }
      final genre = ch?.genre?.trim();
      if (genre != null && genre.isNotEmpty) {
        // Split combined genres ("Aksiyon, Macera") so each genre
        // gets credit for the time, then divide so totals don't
        // double-count.
        final parts = genre
            .split(RegExp(r'[,&·/]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          final share = secs ~/ parts.length;
          for (final g in parts) {
            genreSeconds.update(g, (v) => v + share,
                ifAbsent: () => share);
          }
        }
      } else if (cat != null && cat.name.isNotEmpty) {
        // Fallback: use the catalogue category name when the channel
        // has no genre column populated (common for Xtream feeds).
        genreSeconds.update(cat.name, (v) => v + secs,
            ifAbsent: () => secs);
      }
    }
    final topGenres = (genreSeconds.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => e.key)
        .toList();
    return _StatsSnapshot(
      totalMinutes: totalSeconds ~/ 60,
      finishedMovies: movies,
      finishedEpisodes: episodes,
      topGenres: topGenres,
    );
  }
}

enum _StatsBucket { allTime, thisMonth, thisWeek }

class _StatsSnapshot {
  final int totalMinutes;
  final int finishedMovies;
  final int finishedEpisodes;
  final List<String> topGenres;
  const _StatsSnapshot({
    required this.totalMinutes,
    required this.finishedMovies,
    required this.finishedEpisodes,
    required this.topGenres,
  });
}

class _StatBigNumberRow extends StatelessWidget {
  final String primaryValue;
  final String primaryLabel;
  const _StatBigNumberRow({
    required this.primaryValue,
    required this.primaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primaryLabel,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            primaryValue,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceElevatedDark
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondaryDark,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// Data Section
class _DataSection extends ConsumerWidget {
  final AppLocalizations l10n;
  const _DataSection({required this.l10n});

  Future<void> _clearCaches(BuildContext context) async {
    ApiCache.instance.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.cacheClearedMsg)),
    );
  }

  Future<void> _resetContentData(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        title: Text(
          l10n.resetContentData,
          style: const TextStyle(color: AppColors.textDark),
        ),
        content: Text(
          l10n.resetContentDataConfirm,
          style: const TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.reset),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final db = ref.read(appDatabaseProvider);
    await db.delete(db.channels).go();
    await db.delete(db.categories).go();
    await db.delete(db.programs).go();
    ApiCache.instance.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.resetContentDataDone)),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      // Storage Access Framework picker — user chooses Downloads /
      // Drive / SD card / wherever. File ends up OUTSIDE the app
      // sandbox so a future uninstall doesn't take the backup with
      // it (the trap the v1.1 builds fell into).
      final path = await ref
          .read(backupServiceProvider)
          .exportToUserPickedFile();
      if (!context.mounted) return;
      if (path == null) {
        // User dismissed the picker. No-op snack to avoid the
        // "where did my file go" panic — silently exit.
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.backupSaved}\n$path'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.backupFailed}: $e')),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
    );
    final filePath = pick?.files.single.path;
    if (filePath == null) return;
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevatedDark,
        title: Text(
          l10n.restoreFromBackup,
          style: const TextStyle(color: AppColors.textDark),
        ),
        content: Text(
          l10n.restoreConfirm,
          style: const TextStyle(color: AppColors.textSecondaryDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.restoreFromBackup),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(backupServiceProvider).importFromFile(filePath);
      // Force every account/settings provider to re-read from the new state.
      ref.invalidate(savedAccountsProvider);
      ref.invalidate(currentAccountProvider);
      ref.invalidate(settingsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupRestored)),
      );
    } on FormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupInvalidFormat)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.backupFailed}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final surfaceColor = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(
        l10n.dataBackup,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor),
      ),
      const SizedBox(height: 24),
      ListTile(
        leading: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
        title: Text(l10n.backupNow, style: TextStyle(color: textColor)),
        subtitle: Text(
          l10n.backupNowDesc,
          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: surfaceColor,
        onTap: () => _exportBackup(context, ref),
      ),
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.restore, color: AppColors.primary),
        title: Text(l10n.restoreFromBackup, style: TextStyle(color: textColor)),
        subtitle: Text(
          l10n.restoreFromBackupDesc,
          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: surfaceColor,
        onTap: () => _importBackup(context, ref),
      ),
      const SizedBox(height: 12),
      // Same-network device-to-device transfer (no cloud / file).
      ListTile(
        leading: const Icon(Icons.devices_other, color: AppColors.primary),
        title: Text(l10n.deviceSync, style: TextStyle(color: textColor)),
        subtitle: Text(
          l10n.deviceSyncDesc,
          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: surfaceColor,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const DeviceSyncScreen(),
        )),
      ),
      const SizedBox(height: 24),
      Divider(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.delete_outline, color: AppColors.primary),
        title: Text(l10n.clearCache, style: TextStyle(color: textColor)),
        subtitle: Text(
          l10n.clearCacheDesc,
          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: surfaceColor,
        onTap: () => _clearCaches(context),
      ),
      const SizedBox(height: 12),
      ListTile(
        leading: const Icon(Icons.cleaning_services_outlined, color: Colors.orange),
        title: Text(
          l10n.resetContentData,
          style: TextStyle(color: textColor),
        ),
        subtitle: Text(
          l10n.resetContentDataDesc,
          style: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 13),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: surfaceColor,
        onTap: () => _resetContentData(context, ref),
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
