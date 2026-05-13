import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/presentation/widgets/layout/app_shell_back_resolver.dart';

void main() {
  // Fixed reference moment for all "lastBackPress vs now" comparisons.
  final t0 = DateTime(2025, 1, 1, 12, 0, 0);
  DateTime later(Duration d) => t0.add(d);

  group('AppShellBackResolver — screen handler claim', () {
    test('screen handler handled → consumed', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: true,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: false,
        currentBranchIndex: 2,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.consumed);
    });

    test(
      'screen-claimed press wins over everything else, even with a fresh '
      'lastBackPress that would otherwise exit',
      () {
        final action = resolveAppShellBackAction(
          screenHandlerHandled: true,
          isDesktopPlatform: true,
          sidebarMounted: true,
          sidebarHasFocus: true,
          currentBranchIndex: 0,
          lastBackPress: t0,
          now: later(const Duration(milliseconds: 500)),
        );
        expect(action, AppShellBackAction.consumed);
      },
    );
  });

  group('AppShellBackResolver — desktop/TV sidebar bounce', () {
    test('focus on content → focusSidebar', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: false,
        currentBranchIndex: 2,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.focusSidebar);
    });

    test('also fires on Dashboard branch when sidebar not focused', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: false,
        currentBranchIndex: 0,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.focusSidebar,
          reason: 'Dashboard with content focused must first surface the '
              'sidebar — without this the exit dance steals the only path '
              'TV users have to the nav.');
    });

    test('sidebar not mounted → skip bounce', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: false,
        sidebarHasFocus: false,
        currentBranchIndex: 2,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.goToDashboard);
    });

    test('mobile platform → skip bounce', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: false,
        sidebarMounted: false,
        sidebarHasFocus: false,
        currentBranchIndex: 2,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.goToDashboard);
    });
  });

  group('AppShellBackResolver — branch navigation', () {
    test(
      'sidebar focused + non-Dashboard branch → goToDashboard',
      () {
        final action = resolveAppShellBackAction(
          screenHandlerHandled: false,
          isDesktopPlatform: true,
          sidebarMounted: true,
          sidebarHasFocus: true,
          currentBranchIndex: 2,
          lastBackPress: null,
          now: t0,
        );
        expect(action, AppShellBackAction.goToDashboard);
      },
    );

    test('mobile + non-Dashboard branch → goToDashboard', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: false,
        sidebarMounted: false,
        sidebarHasFocus: false,
        currentBranchIndex: 3,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.goToDashboard);
    });
  });

  group('AppShellBackResolver — Dashboard exit dance', () {
    test('first back on Dashboard + sidebar focused → showExitConfirm', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: true,
        currentBranchIndex: 0,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.showExitConfirm);
    });

    test('second back within window → exit', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: true,
        currentBranchIndex: 0,
        lastBackPress: t0,
        now: later(const Duration(milliseconds: 1500)),
      );
      expect(action, AppShellBackAction.exit);
    });

    test('second back after window expired → showExitConfirm again', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: true,
        currentBranchIndex: 0,
        lastBackPress: t0,
        now: later(const Duration(seconds: 3)),
      );
      expect(action, AppShellBackAction.showExitConfirm);
    });

    test('custom exitConfirmWindow honored', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: true,
        sidebarMounted: true,
        sidebarHasFocus: true,
        currentBranchIndex: 0,
        lastBackPress: t0,
        now: later(const Duration(milliseconds: 800)),
        exitConfirmWindow: const Duration(milliseconds: 500),
      );
      expect(action, AppShellBackAction.showExitConfirm,
          reason: 'lastBackPress is OUTSIDE the shortened window, so exit '
              'should not fire.');
    });
  });

  group('AppShellBackResolver — mobile Dashboard exit', () {
    test('mobile + Dashboard + no lastBackPress → showExitConfirm', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: false,
        sidebarMounted: false,
        sidebarHasFocus: false,
        currentBranchIndex: 0,
        lastBackPress: null,
        now: t0,
      );
      expect(action, AppShellBackAction.showExitConfirm);
    });

    test('mobile + Dashboard + recent lastBackPress → exit', () {
      final action = resolveAppShellBackAction(
        screenHandlerHandled: false,
        isDesktopPlatform: false,
        sidebarMounted: false,
        sidebarHasFocus: false,
        currentBranchIndex: 0,
        lastBackPress: t0,
        now: later(const Duration(seconds: 1)),
      );
      expect(action, AppShellBackAction.exit);
    });
  });
}
