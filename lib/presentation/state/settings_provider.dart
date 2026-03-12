import 'package:lifeostv/data/repositories/settings_repository.dart';
import 'package:lifeostv/domain/models/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'settings_provider.g.dart';

@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  AppSettings build() {
    final repo = ref.watch(settingsRepositoryProvider);
    return repo.loadSettings();
  }

  void updateSettings(AppSettings newSettings) {
    state = newSettings;
    ref.read(settingsRepositoryProvider).saveSettings(newSettings);
  }

  void setTheme(AppThemeMode mode) {
    updateSettings(state.copyWith(themeMode: mode));
  }

  void setLanguage(AppLanguage lang) {
    updateSettings(state.copyWith(language: lang));
  }

  void setDefaultAccount(int accountId) {
    updateSettings(state.copyWith(defaultAccountId: accountId));
    ref.read(settingsRepositoryProvider).setDefaultAccount(accountId);
  }
}
