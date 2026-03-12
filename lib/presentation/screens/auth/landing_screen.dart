import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeostv/config/theme.dart';
import 'package:lifeostv/l10n/generated/app_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifeostv/presentation/state/auth_provider.dart';

class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final accountsAsync = ref.watch(savedAccountsProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo area
            const Icon(Icons.tv, size: 80, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              l10n.appName,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.welcomeMessage,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 32),

            // Saved Accounts
            accountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    Text('Select Account', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    ...accounts.map((account) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AuthOptionCard(
                        title: account.name,
                        icon: Icons.person_pin, 
                        onTap: () => context.go('/dashboard'), // TODO: Set active account
                      ),
                    )),
                    const SizedBox(height: 32),
                    const Divider(endIndent: 100, indent: 100),
                    const SizedBox(height: 32),
                  ],
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, stack) => Text('Error loading accounts: $err'),
            ),
            
            // Options
            _AuthOptionCard(
              title: l10n.loginWithXtream,
              icon: Icons.login,
              onTap: () => context.go('/auth/xtream'),
            ),
            const SizedBox(height: 24),
            _AuthOptionCard(
              title: l10n.loadM3U,
              icon: Icons.playlist_add,
              onTap: () => context.go('/auth/m3u'),
            ),
             const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {}, // TODO: Implement Backup Restore
              icon: const Icon(Icons.restore),
              label: Text(l10n.restoreBackup),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthOptionCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _AuthOptionCard({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_AuthOptionCard> createState() => _AuthOptionCardState();
}

class _AuthOptionCardState extends State<_AuthOptionCard> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 400,
            padding: const EdgeInsets.all(24),
            transform: Matrix4.identity()..scale(_isFocused || _isHovered ? 1.05 : 1.0),
            decoration: BoxDecoration(
              color: _isFocused || _isHovered 
                  ? AppColors.primary 
                  : Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: _isFocused || _isHovered
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha:0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon, 
                  size: 32, 
                  color: _isFocused || _isHovered ? Colors.white : Theme.of(context).iconTheme.color
                ),
                const SizedBox(width: 16),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _isFocused || _isHovered ? Colors.white : null,
                        fontWeight: FontWeight.bold,
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
