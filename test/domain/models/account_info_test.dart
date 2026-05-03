import 'package:flutter_test/flutter_test.dart';

import 'package:lifeostv/domain/models/account_info.dart';

void main() {
  group('AccountInfo.fromXtreamResponse', () {
    test('parses status, exp_date and connection counts', () {
      final info = AccountInfo.fromXtreamResponse({
        'user_info': {
          'status': 'Active',
          'exp_date': '1735689600', // 2025-01-01 UTC, seconds
          'max_connections': '3',
          'active_cons': '1',
          'created_at': '1700000000',
          'is_trial': '0',
        },
      });
      expect(info.status, 'Active');
      expect(info.maxConnections, 3);
      expect(info.activeConnections, 1);
      expect(info.isTrial, isFalse);
      // exp_date is in seconds; the model converts to DateTime via *1000.
      expect(info.expiryDate?.year, 2025);
      expect(info.createdAt?.year, anyOf([2023, 2024])); // tz-dependent
    });

    test('handles missing user_info gracefully', () {
      final info = AccountInfo.fromXtreamResponse({});
      expect(info.status, 'Unknown');
      expect(info.expiryDate, isNull);
      expect(info.maxConnections, 0);
    });

    test('exp_date "0" is treated as no expiry', () {
      final info = AccountInfo.fromXtreamResponse({
        'user_info': {'status': 'Active', 'exp_date': '0'},
      });
      expect(info.expiryDate, isNull);
    });

    test('is_trial == "1" → isTrial true', () {
      final info = AccountInfo.fromXtreamResponse({
        'user_info': {'status': 'Active', 'is_trial': '1'},
      });
      expect(info.isTrial, isTrue);
    });
  });

  group('AccountInfo computed properties', () {
    test('isActive requires Active status AND non-expired date', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final past = DateTime.now().subtract(const Duration(days: 1));

      expect(
        AccountInfo(status: 'Active', expiryDate: future).isActive,
        isTrue,
      );
      expect(
        AccountInfo(status: 'Active', expiryDate: past).isActive,
        isFalse,
        reason: 'Active label cannot override an elapsed expiry',
      );
      expect(
        AccountInfo(status: 'Banned', expiryDate: future).isActive,
        isFalse,
      );
    });

    test('isExpired catches both Expired status and elapsed date', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(AccountInfo(status: 'Expired').isExpired, isTrue);
      expect(AccountInfo(status: 'Active', expiryDate: past).isExpired, isTrue);
      expect(
        AccountInfo(
          status: 'Active',
          expiryDate: DateTime.now().add(const Duration(days: 7)),
        ).isExpired,
        isFalse,
      );
    });

    test('remainingDays clamps to 0 for expired accounts', () {
      final past = DateTime.now().subtract(const Duration(days: 5));
      expect(AccountInfo(status: 'Expired', expiryDate: past).remainingDays, 0);
    });

    test('remainingDays is null when expiry is null', () {
      expect(AccountInfo(status: 'Active').remainingDays, isNull);
    });

    test('remainingDays counts forward correctly', () {
      final in10 = DateTime.now().add(const Duration(days: 10, hours: 1));
      final r = AccountInfo(status: 'Active', expiryDate: in10).remainingDays;
      expect(r, anyOf([10, 9])); // tz/clock-edge-tolerant
    });
  });

  group('AccountInfo.toMap / fromMap round-trip', () {
    test('preserves every field', () {
      final original = AccountInfo(
        status: 'Active',
        expiryDate: DateTime.utc(2026, 5, 1),
        maxConnections: 5,
        activeConnections: 2,
        createdAt: DateTime.utc(2024, 1, 15),
        isTrial: true,
      );
      final restored = AccountInfo.fromMap(original.toMap());

      expect(restored.status, original.status);
      expect(restored.maxConnections, original.maxConnections);
      expect(restored.activeConnections, original.activeConnections);
      expect(restored.isTrial, original.isTrial);
      expect(
        restored.expiryDate!.millisecondsSinceEpoch,
        original.expiryDate!.millisecondsSinceEpoch,
      );
      expect(
        restored.createdAt!.millisecondsSinceEpoch,
        original.createdAt!.millisecondsSinceEpoch,
      );
    });

    test('tolerates a map with missing keys (legacy SharedPreferences)', () {
      final restored = AccountInfo.fromMap({'status': 'Active'});
      expect(restored.status, 'Active');
      expect(restored.expiryDate, isNull);
      expect(restored.maxConnections, 0);
    });
  });
}
