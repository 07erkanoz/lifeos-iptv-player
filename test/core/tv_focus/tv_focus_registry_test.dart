import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/core/tv_focus/tv_focus_registry.dart';

void main() {
  group('TvFocusRegistry main sidebar', () {
    test('requestMainSidebar returns false when nothing registered', () {
      final reg = TvFocusRegistry();
      expect(reg.requestMainSidebar(), isFalse);
    });

    test('requestMainSidebar fires the registered callback', () {
      final reg = TvFocusRegistry();
      var fired = 0;
      reg.registerMainSidebar(() => fired++);
      expect(reg.requestMainSidebar(), isTrue);
      expect(fired, 1);
    });

    test('unregisterMainSidebar only clears the matching callback', () {
      final reg = TvFocusRegistry();
      void oldCb() {}
      void newCb() {}
      reg.registerMainSidebar(oldCb);
      reg.registerMainSidebar(newCb); // replaces oldCb
      // Late unregister from oldCb's owner must not wipe newCb.
      reg.unregisterMainSidebar(oldCb);
      expect(
        reg.requestMainSidebar(),
        isTrue,
        reason: 'newCb should still be active after stale unregister',
      );
    });
  });

  group('TvFocusRegistry branch primary', () {
    test('requestActivePrimary returns false with no registrations', () {
      final reg = TvFocusRegistry();
      expect(reg.requestActivePrimary(0), isFalse);
    });

    test('routes to the matching branch index', () {
      final reg = TvFocusRegistry();
      final fired = <int>[];
      reg.registerBranchPrimary(0, () => fired.add(0));
      reg.registerBranchPrimary(2, () => fired.add(2));
      reg.requestActivePrimary(0);
      reg.requestActivePrimary(2);
      reg.requestActivePrimary(1); // no registration → no-op
      expect(fired, [0, 2]);
    });

    test('unregister only removes the exact callback', () {
      final reg = TvFocusRegistry();
      void oldCb() {}
      void newCb() {}
      reg.registerBranchPrimary(0, oldCb);
      reg.registerBranchPrimary(0, newCb);
      reg.unregisterBranchPrimary(0, oldCb); // stale, shouldn't wipe newCb
      expect(reg.requestActivePrimary(0), isTrue);
    });
  });

  group('TvFocusRegistry overlay priority', () {
    test('overlay takes precedence over branch primary', () {
      final reg = TvFocusRegistry();
      var branchFired = 0;
      var overlayFired = 0;
      reg.registerBranchPrimary(0, () => branchFired++);
      reg.pushOverlayPrimary(0, () => overlayFired++);

      reg.requestActivePrimary(0);
      expect(overlayFired, 1);
      expect(
        branchFired,
        0,
        reason: 'branch must not fire while an overlay is active',
      );
    });

    test('popOverlayPrimary restores branch as the active target', () {
      final reg = TvFocusRegistry();
      var branchFired = 0;
      var overlayFired = 0;
      void overlay() => overlayFired++;
      reg.registerBranchPrimary(0, () => branchFired++);
      reg.pushOverlayPrimary(0, overlay);
      reg.popOverlayPrimary(0, overlay);

      reg.requestActivePrimary(0);
      expect(branchFired, 1);
      expect(overlayFired, 0);
    });

    test('popOverlayPrimary ignores a stale callback', () {
      final reg = TvFocusRegistry();
      void oldOverlay() {}
      var newOverlayFired = 0;
      reg.pushOverlayPrimary(0, oldOverlay);
      reg.pushOverlayPrimary(0, () => newOverlayFired++); // replaces oldOverlay
      reg.popOverlayPrimary(0, oldOverlay); // stale → ignored

      reg.requestActivePrimary(0);
      expect(
        newOverlayFired,
        1,
        reason: 'newer overlay must survive stale pop',
      );
    });
  });
  test('offstage detail cannot capture another branch focus or back', () {
    final reg = TvFocusRegistry();
    final events = <String>[];
    reg.registerBranchPrimary(1, () => events.add('live'));
    reg.pushOverlayPrimary(2, () => events.add('movie detail'));
    reg.pushOverlayPrimary(3, () => events.add('series detail'));
    reg.registerBranchBack(2, () {
      events.add('movie back');
      return true;
    });
    reg.registerBranchBack(3, () {
      events.add('series back');
      return true;
    });
    reg.requestActivePrimary(1);
    reg.requestActivePrimary(2);
    expect(reg.handleBranchBack(1), isFalse);
    expect(reg.handleBranchBack(3), isTrue);
    expect(events, ['live', 'movie detail', 'series back']);
  });

  test('stale back unregister cannot remove the replacement', () {
    final reg = TvFocusRegistry();
    bool old() => false;
    bool current() => true;
    reg.registerBranchBack(2, old);
    reg.registerBranchBack(2, current);
    reg.unregisterBranchBack(2, old);
    expect(reg.handleBranchBack(2), isTrue);
    reg.unregisterBranchBack(2, current);
    expect(reg.handleBranchBack(2), isFalse);
  });
}
