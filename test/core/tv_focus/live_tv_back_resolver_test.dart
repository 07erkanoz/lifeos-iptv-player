import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/live_tv_back_resolver.dart';

void main() {
  group('resolveLiveTvBackAction — sidebar handoff', () {
    test('main sidebar focused → handToShell (AppShell takes over)', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: true,
          categoriesCollapsed: false,
          categoryScopeFocused: false,
          epgFocused: false,
          channelListFocused: false,
        ),
        LiveTvBackAction.handToShell,
      );
    });

    test('main sidebar wins over all other zone flags', () {
      // Defensive: even if a stale signal says EPG also focused,
      // sidebar precedence keeps the outer ladder consistent.
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: true,
          categoriesCollapsed: false,
          categoryScopeFocused: true,
          epgFocused: true,
          channelListFocused: true,
        ),
        LiveTvBackAction.handToShell,
      );
    });
  });

  group('resolveLiveTvBackAction — category panel layer', () {
    test('category focused → handToShell (AppShell moves to main sidebar)', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: false,
          categoryScopeFocused: true,
          epgFocused: false,
          channelListFocused: false,
        ),
        LiveTvBackAction.handToShell,
      );
    });

    test('category collapsed → reopens categories', () {
      // Channel list focused but no category panel available → fall
      // through to handToShell instead of trying to bounce to a
      // non-existent panel.
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: true,
          categoryScopeFocused: false,
          epgFocused: false,
          channelListFocused: true,
        ),
        LiveTvBackAction.focusCategorySidebar,
      );
    });
  });

  group('resolveLiveTvBackAction — EPG layer', () {
    test('EPG focused → focusChannelList', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: false,
          categoryScopeFocused: false,
          epgFocused: true,
          channelListFocused: false,
        ),
        LiveTvBackAction.focusChannelList,
      );
    });

    test('EPG focused → focusChannelList even when categories collapsed', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: true,
          categoryScopeFocused: false,
          epgFocused: true,
          channelListFocused: false,
        ),
        LiveTvBackAction.focusChannelList,
      );
    });
  });

  group('resolveLiveTvBackAction — channel list layer', () {
    test('channel list focused + categories open → focusCategorySidebar', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: false,
          categoryScopeFocused: false,
          epgFocused: false,
          channelListFocused: true,
        ),
        LiveTvBackAction.focusCategorySidebar,
      );
    });

    test('channel list focused + categories collapsed → reopen panel', () {
      expect(
        resolveLiveTvBackAction(
          mainSidebarFocused: false,
          categoriesCollapsed: true,
          categoryScopeFocused: false,
          epgFocused: false,
          channelListFocused: true,
        ),
        LiveTvBackAction.focusCategorySidebar,
      );
    });
  });

  group('resolveLiveTvBackAction — full back ladder', () {
    test('walks one zone outward per press', () {
      // Start: EPG focused, categories open.
      var action = resolveLiveTvBackAction(
        mainSidebarFocused: false,
        categoriesCollapsed: false,
        categoryScopeFocused: false,
        epgFocused: true,
        channelListFocused: false,
      );
      expect(action, LiveTvBackAction.focusChannelList);

      // After EPG → channel list. Now channel list focused.
      action = resolveLiveTvBackAction(
        mainSidebarFocused: false,
        categoriesCollapsed: false,
        categoryScopeFocused: false,
        epgFocused: false,
        channelListFocused: true,
      );
      expect(action, LiveTvBackAction.focusCategorySidebar);

      // After channel list → category panel. Now category focused.
      action = resolveLiveTvBackAction(
        mainSidebarFocused: false,
        categoriesCollapsed: false,
        categoryScopeFocused: true,
        epgFocused: false,
        channelListFocused: false,
      );
      expect(action, LiveTvBackAction.handToShell);

      // After category → main sidebar (AppShell). Now sidebar focused.
      action = resolveLiveTvBackAction(
        mainSidebarFocused: true,
        categoriesCollapsed: false,
        categoryScopeFocused: false,
        epgFocused: false,
        channelListFocused: false,
      );
      expect(action, LiveTvBackAction.handToShell);
    });

    test('with collapsed categories the ladder reopens that zone', () {
      // EPG → channel list.
      var action = resolveLiveTvBackAction(
        mainSidebarFocused: false,
        categoriesCollapsed: true,
        categoryScopeFocused: false,
        epgFocused: true,
        channelListFocused: false,
      );
      expect(action, LiveTvBackAction.focusChannelList);

      // Channel list → reopen categories.
      action = resolveLiveTvBackAction(
        mainSidebarFocused: false,
        categoriesCollapsed: true,
        categoryScopeFocused: false,
        epgFocused: false,
        channelListFocused: true,
      );
      expect(action, LiveTvBackAction.focusCategorySidebar);
    });
  });
}
