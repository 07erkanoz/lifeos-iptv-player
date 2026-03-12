import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class M3UUploadScreen extends ConsumerStatefulWidget {
  const M3UUploadScreen({super.key});

  @override
  ConsumerState<M3UUploadScreen> createState() => _M3UUploadScreenState();
}

class _M3UUploadScreenState extends ConsumerState<M3UUploadScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _urlFocusNode = FocusNode();
  final _loadButtonFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _errorMessage;
  SyncProgress _syncProgress = const SyncProgress();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _loadButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLoad() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim().isEmpty ? 'M3U Playlist' : _nameController.text.trim();
      await ref.read(authRepositoryProvider).loadM3U(_urlController.text.trim(), name: name);

      if (!mounted) return;

      // Account saved -> start syncing data
      setState(() {
        _isLoading = false;
        _isSyncing = true;
      });

      // Clear old account data (cache, favorites, history)
      final authRepo = ref.read(authRepositoryProvider);
      if (authRepo is AuthRepositoryImpl) {
        await authRepo.clearUserDataForNewAccount();
      }

      // Get the newly created account
      final account = await ref.read(authRepositoryProvider).getCurrentAccount();
      if (account == null) {
        if (mounted) {
          setState(() {
            _isSyncing = false;
            _errorMessage = 'Account was not saved properly';
          });
        }
        return;
      }

      // Sync data for both Xtream and M3U accounts
      await ref.read(syncServiceProvider).syncAllWithProgress(account, (progress) {
        if (mounted) {
          setState(() => _syncProgress = progress);
        }
      });

      if (mounted) {
        ref.invalidate(savedAccountsProvider);
        ref.invalidate(currentAccountProvider);
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSyncing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // While syncing, show full-screen progress
    if (_isSyncing) {
      return Scaffold(
        body: PopScope(
          canPop: false,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                  const SizedBox(height: 24),
                  Text(
                    _syncProgress.step.isNotEmpty ? _syncProgress.step : 'Loading playlist data...',
                    style: const TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 24),
                  _buildSyncStats(),
                  const SizedBox(height: 16),
                  Text(
                    'Please wait, do not close the app',
                    style: TextStyle(color: AppColors.textTertiaryDark, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loadM3U),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(24),
            child: FocusTraversalGroup(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.playlist_play, size: 64, color: AppColors.primary),
                const SizedBox(height: 32),

                // Error banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Hint about auto-detection
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Xtream M3U links (with username & password) are auto-detected.',
                          style: TextStyle(color: AppColors.textSecondaryDark, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Playlist Name',
                    prefixIcon: Icon(Icons.label_outline),
                    hintText: 'e.g. My Playlist',
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _urlFocusNode.requestFocus(),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _urlController,
                  focusNode: _urlFocusNode,
                  decoration: InputDecoration(
                    labelText: l10n.url,
                    prefixIcon: const Icon(Icons.link),
                    hintText: 'http://example.com/get.php?username=...&password=...',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _loadButtonFocusNode.requestFocus(),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    focusNode: _loadButtonFocusNode,
                    onPressed: _isLoading ? null : _handleLoad,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                    ),
                    icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.cloud_download),
                    label: _isLoading
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Load Playlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        children: [
          _buildStatRow(Icons.category_outlined, 'Categories', _syncProgress.categoryCount),
          const SizedBox(height: 12),
          _buildStatRow(Icons.live_tv, 'Live Channels', _syncProgress.liveCount),
          const SizedBox(height: 12),
          _buildStatRow(Icons.movie_outlined, 'Movies', _syncProgress.movieCount),
          const SizedBox(height: 12),
          _buildStatRow(Icons.tv, 'Series', _syncProgress.seriesCount),
        ],
      ),
    );
  }

  Widget _buildStatRow(IconData icon, String label, int count) {
    final isActive = count > 0;
    return Row(
      children: [
        Icon(icon, size: 18, color: isActive ? AppColors.primary : AppColors.textTertiaryDark),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.textDark : AppColors.textTertiaryDark,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        if (isActive)
          Text(
            count.toString(),
            style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w700),
          )
        else
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.textTertiaryDark,
            ),
          ),
      ],
    );
  }
}
