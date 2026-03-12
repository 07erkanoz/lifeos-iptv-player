import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/datasources/local/database.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/repositories/content_repository.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

/// Provider that watches all categories (including hidden) for editing
final _allCategoriesProvider = StreamProvider.family<List<Category>, String>((ref, type) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchAllCategories(type);
});

class AccountEditScreen extends ConsumerStatefulWidget {
  final Account account;
  const AccountEditScreen({super.key, required this.account});

  @override
  ConsumerState<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends ConsumerState<AccountEditScreen> with SingleTickerProviderStateMixin {
  late TextEditingController _nameController;
  late TabController _tabController;
  bool _nameChanged = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _tabController = TabController(length: 3, vsync: this);
    _nameController.addListener(() {
      if (_nameController.text != widget.account.name && !_nameChanged) {
        setState(() => _nameChanged = true);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await ref.read(authRepositoryProvider).updateAccountName(widget.account.id, name);
    ref.invalidate(savedAccountsProvider);
    if (mounted) {
      setState(() => _nameChanged = false);
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountNameUpdated)),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.deleteAccount),
          content: Text(l10n.deleteAccountConfirm(widget.account.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(authRepositoryProvider).deleteAccount(widget.account.id);
      ref.invalidate(savedAccountsProvider);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editAccount(widget.account.name)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: l10n.deleteAccount,
            onPressed: _deleteAccount,
          ),
        ],
      ),
      body: Column(
        children: [
          // Name Edit Section
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: l10n.accountName,
                      prefixIcon: const Icon(Icons.label_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (_nameChanged) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _saveName,
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(l10n.save),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Account Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Icon(widget.account.type == 'xtream' ? Icons.dns : Icons.playlist_play, size: 18, color: AppColors.textSecondaryDark),
                const SizedBox(width: 8),
                Text(widget.account.type.toUpperCase(), style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 16),
                Expanded(child: Text(widget.account.url, style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Category Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondaryDark,
              indicatorColor: AppColors.primary,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: l10n.liveTV),
                Tab(text: l10n.movies),
                Tab(text: l10n.series),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Category Lists
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _CategoryList(type: 'live'),
                _CategoryList(type: 'movie'),
                _CategoryList(type: 'series'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  final String type;
  const _CategoryList({required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.watch(_allCategoriesProvider(type));

    return categoriesAsync.when(
      data: (categories) {
        if (categories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined, size: 48, color: AppColors.textDisabledDark),
                const SizedBox(height: 12),
                Text(l10n.noCategories, style: TextStyle(color: AppColors.textSecondaryDark)),
              ],
            ),
          );
        }

        final visible = categories.where((c) => !c.isHidden).toList();
        final hidden = categories.where((c) => c.isHidden).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          children: [
            // Stats
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(l10n.visibleCount(visible.length), style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  if (hidden.isNotEmpty)
                    Text(l10n.hiddenCount(hidden.length), style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 13)),
                ],
              ),
            ),

            // Visible categories
            ...visible.map((cat) => _CategoryTile(category: cat, isDark: isDark)),

            // Hidden categories
            if (hidden.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(l10n.hiddenLabel, style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              ...hidden.map((cat) => _CategoryTile(category: cat, isDark: isDark)),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('${l10n.error}: $err')),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  final Category category;
  final bool isDark;
  const _CategoryTile({required this.category, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        title: Text(
          category.name,
          style: TextStyle(
            color: category.isHidden ? AppColors.textTertiaryDark : (isDark ? AppColors.textDark : AppColors.textLight),
            fontWeight: FontWeight.w500,
            decoration: category.isHidden ? TextDecoration.lineThrough : null,
          ),
        ),
        leading: Icon(
          category.isHidden ? Icons.visibility_off : Icons.visibility,
          color: category.isHidden ? AppColors.textTertiaryDark : AppColors.primary,
          size: 20,
        ),
        trailing: Switch(
          value: !category.isHidden,
          onChanged: (visible) {
            ref.read(contentRepositoryProvider).toggleCategoryHidden(category.id, category.type, !visible);
            ref.invalidate(_allCategoriesProvider(category.type));
          },
          activeColor: AppColors.primary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    );
  }
}
