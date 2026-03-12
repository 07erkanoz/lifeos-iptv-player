import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/data/repositories/auth_repository_impl.dart';
import 'package:lifeostv/data/services/sync_service.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

class XtreamLoginScreen extends ConsumerStatefulWidget {
  const XtreamLoginScreen({super.key});

  @override
  ConsumerState<XtreamLoginScreen> createState() => _XtreamLoginScreenState();
}

class _XtreamLoginScreenState extends ConsumerState<XtreamLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _urlFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _loginButtonFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _obscurePassword = true;
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
    _usernameController.dispose();
    _passwordController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _loginButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim().isEmpty ? 'Xtream Account' : _nameController.text.trim();
      await ref.read(authRepositoryProvider).loginXtream(
            _urlController.text.trim(),
            _usernameController.text.trim(),
            _passwordController.text.trim(),
            name: name,
          );

      if (!mounted) return;

      // Login succeeded -> start syncing data
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
        setState(() {
          _isSyncing = false;
          _errorMessage = 'Account was not saved properly';
        });
        return;
      }

      // Sync with progress
      await ref.read(syncServiceProvider).syncAllWithProgress(account, (progress) {
        if (mounted) {
          setState(() => _syncProgress = progress);
        }
      });

      if (mounted) {
        // Invalidate providers so dashboard reloads fresh data
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
          canPop: false, // Prevent back during sync
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
                    _syncProgress.step.isNotEmpty ? _syncProgress.step : 'Connecting...',
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
        title: Text(l10n.loginWithXtream),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: FocusTraversalGroup(
              child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   const Icon(Icons.dns, size: 64, color: AppColors.primary),
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

                   // Name Input (autofocus for TV)
                   TextFormField(
                     controller: _nameController,
                     focusNode: _nameFocusNode,
                     decoration: const InputDecoration(
                       labelText: 'Account Name',
                       prefixIcon: Icon(Icons.label_outline),
                       hintText: 'e.g. My IPTV',
                     ),
                     textInputAction: TextInputAction.next,
                     onFieldSubmitted: (_) => _urlFocusNode.requestFocus(),
                   ),
                   const SizedBox(height: 16),

                   // URL Input
                   TextFormField(
                     controller: _urlController,
                     focusNode: _urlFocusNode,
                     decoration: InputDecoration(
                       labelText: l10n.url,
                       prefixIcon: const Icon(Icons.link),
                       hintText: 'http://example.com:8080',
                     ),
                     validator: (value) {
                       if (value == null || value.trim().isEmpty) {
                         return 'Please enter URL';
                       }
                       return null;
                     },
                     textInputAction: TextInputAction.next,
                     keyboardType: TextInputType.url,
                     onFieldSubmitted: (_) => _usernameFocusNode.requestFocus(),
                   ),
                   const SizedBox(height: 16),

                   // Username Input
                   TextFormField(
                     controller: _usernameController,
                     focusNode: _usernameFocusNode,
                     decoration: InputDecoration(
                       labelText: l10n.username,
                       prefixIcon: const Icon(Icons.person),
                     ),
                     validator: (value) {
                       if (value == null || value.trim().isEmpty) {
                         return 'Please enter username';
                       }
                       return null;
                     },
                     textInputAction: TextInputAction.next,
                     onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                   ),
                   const SizedBox(height: 16),

                   // Password Input
                   TextFormField(
                     controller: _passwordController,
                     focusNode: _passwordFocusNode,
                     obscureText: _obscurePassword,
                     decoration: InputDecoration(
                       labelText: l10n.password,
                       prefixIcon: const Icon(Icons.lock),
                       suffixIcon: IconButton(
                         icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                         onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                       ),
                     ),
                     validator: (value) {
                       if (value == null || value.trim().isEmpty) {
                         return 'Please enter password';
                       }
                       return null;
                     },
                     onFieldSubmitted: (_) => _loginButtonFocusNode.requestFocus(),
                     textInputAction: TextInputAction.next,
                   ),
                   const SizedBox(height: 32),

                   // Login Button
                   SizedBox(
                     height: 50,
                     child: ElevatedButton(
                       focusNode: _loginButtonFocusNode,
                       onPressed: _isLoading ? null : _handleLogin,
                       style: ElevatedButton.styleFrom(
                         backgroundColor: AppColors.primary,
                         foregroundColor: Colors.white,
                         shape: RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(8),
                         ),
                       ),
                       child: _isLoading
                           ? const SizedBox(
                               height: 24,
                               width: 24,
                               child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                             )
                           : Text(l10n.login, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                     ),
                   ),
                ],
              ),
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
