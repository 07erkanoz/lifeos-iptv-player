import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/grid_screen_back_resolver.dart';

void main() {
  group('resolveGridScreenBackAction — detail layer', () {
    test('detail open → closeDetail regardless of other state', () {
      // Even with main sidebar focused, detail-open beats everything.
      expect(
        resolveGridScreenBackAction(
          detailOpen: true,
          mainSidebarFocused: true,
          categoriesCollapsed: false,
          categoryScopeFocused: true,
        ),
        GridScreenBackAction.closeDetail,
      );

      // Collapsed categories.
      expect(
        resolveGridScreenBackAction(
          detailOpen: true,
          mainSidebarFocused: false,
          categoriesCollapsed: true,
          categoryScopeFocused: false,
        ),
        GridScreenBackAction.closeDetail,
      );
    });
  });

  group('resolveGridScreenBackAction — sidebar handoff', () {
    test('main sidebar focused → handToShell', () {
      expect(
        resolveGridScreenBackAction(
          detailOpen: false,
          mainSidebarFocused: true,
          categoriesCollapsed: false,
          categoryScopeFocused: false,
        ),
        GridScreenBackAction.handToShell,
      );
    });

    test('main sidebar wins over a stale "category also focused" signal', () {
      // Both flags shouldn't be true in practice, but if they ever are,
      // main sidebar focus has priority — that's where the user actually
      // is.
      expect(
        resolveGridScreenBackAction(
          detailOpen: false,
          mainSidebarFocused: true,
          categoriesCollapsed: false,
          categoryScopeFocused: true,
        ),
        GridScreenBackAction.handToShell,
      );
    });
  });

  group('resolveGridScreenBackAction — category layer', () {
    test('category focused → handToShell (AppShell moves to main sidebar)', () {
      expect(
        resolveGridScreenBackAction(
          detailOpen: false,
          mainSidebarFocused: false,
          categoriesCollapsed: false,
          categoryScopeFocused: true,
        ),
        GridScreenBackAction.handToShell,
      );
    });

    test('grid focused + categories open → bounceToCategory', () {
      expect(
        resolveGridScreenBackAction(
          detailOpen: false,
          mainSidebarFocused: false,
          categoriesCollapsed: false,
          categoryScopeFocused: false,
        ),
        GridScreenBackAction.bounceToCategory,
      );
    });

    test('grid focused + categories collapsed → handToShell', () {
      // No intermediate zone to bounce to — let AppShell focus the
      // main sidebar directly.
      expect(
        resolveGridScreenBackAction(
          detailOpen: false,
          mainSidebarFocused: false,
          categoriesCollapsed: true,
          categoryScopeFocused: false,
        ),
        GridScreenBackAction.handToShell,
      );
    });
  });

  group('resolveGridScreenBackAction — full back ladder', () {
    test('walks one zone outward per press without skipping', () {
      // Start: grid focused, categories open. Press 1 → bounceToCategory.
      var action = resolveGridScreenBackAction(
        detailOpen: false,
        mainSidebarFocused: false,
        categoriesCollapsed: false,
        categoryScopeFocused: false,
      );
      expect(action, GridScreenBackAction.bounceToCategory);

      // After bounce: category focused. Press 2 → handToShell (AppShell
      // moves to main sidebar).
      action = resolveGridScreenBackAction(
        detailOpen: false,
        mainSidebarFocused: false,
        categoriesCollapsed: false,
        categoryScopeFocused: true,
      );
      expect(action, GridScreenBackAction.handToShell);

      // After sidebar bounce by AppShell: main sidebar focused.
      // Press 3 → still handToShell (AppShell will goBranch(0)).
      action = resolveGridScreenBackAction(
        detailOpen: false,
        mainSidebarFocused: true,
        categoriesCollapsed: false,
        categoryScopeFocused: false,
      );
      expect(action, GridScreenBackAction.handToShell);
    });
  });
}
