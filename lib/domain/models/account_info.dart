/// Server/User info from Xtream API authentication response.
/// Stored in SharedPreferences, refreshed on login/sync.
class AccountInfo {
  final String status; // "Active", "Expired", "Banned"
  final DateTime? expiryDate;
  final int maxConnections;
  final int activeConnections;
  final DateTime? createdAt;
  final bool isTrial;

  const AccountInfo({
    required this.status,
    this.expiryDate,
    this.maxConnections = 0,
    this.activeConnections = 0,
    this.createdAt,
    this.isTrial = false,
  });

  /// Remaining days until expiry (null if no expiry)
  int? get remainingDays {
    if (expiryDate == null) return null;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get isExpired => status.toLowerCase() == 'expired' ||
      (expiryDate != null && expiryDate!.isBefore(DateTime.now()));

  bool get isActive => status.toLowerCase() == 'active' && !isExpired;

  /// Parse from Xtream API response
  factory AccountInfo.fromXtreamResponse(Map<String, dynamic> data) {
    final userInfo = data['user_info'] as Map<String, dynamic>? ?? {};

    DateTime? expiryDate;
    final expStr = userInfo['exp_date']?.toString();
    if (expStr != null && expStr.isNotEmpty) {
      final ts = int.tryParse(expStr);
      if (ts != null && ts > 0) {
        expiryDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      }
    }

    DateTime? createdAt;
    final createdStr = userInfo['created_at']?.toString();
    if (createdStr != null && createdStr.isNotEmpty) {
      final ts = int.tryParse(createdStr);
      if (ts != null && ts > 0) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      }
    }

    return AccountInfo(
      status: userInfo['status']?.toString() ?? 'Unknown',
      expiryDate: expiryDate,
      maxConnections: int.tryParse(userInfo['max_connections']?.toString() ?? '') ?? 0,
      activeConnections: int.tryParse(userInfo['active_cons']?.toString() ?? '') ?? 0,
      createdAt: createdAt,
      isTrial: userInfo['is_trial']?.toString() == '1',
    );
  }

  /// Serialize to simple map for SharedPreferences
  Map<String, String> toMap() => {
    'status': status,
    'expiry': expiryDate?.millisecondsSinceEpoch.toString() ?? '',
    'max_conn': maxConnections.toString(),
    'active_conn': activeConnections.toString(),
    'created': createdAt?.millisecondsSinceEpoch.toString() ?? '',
    'is_trial': isTrial ? '1' : '0',
  };

  /// Deserialize from SharedPreferences map
  factory AccountInfo.fromMap(Map<String, String> map) {
    DateTime? expiry;
    final expMs = int.tryParse(map['expiry'] ?? '');
    if (expMs != null && expMs > 0) {
      expiry = DateTime.fromMillisecondsSinceEpoch(expMs);
    }

    DateTime? created;
    final createdMs = int.tryParse(map['created'] ?? '');
    if (createdMs != null && createdMs > 0) {
      created = DateTime.fromMillisecondsSinceEpoch(createdMs);
    }

    return AccountInfo(
      status: map['status'] ?? 'Unknown',
      expiryDate: expiry,
      maxConnections: int.tryParse(map['max_conn'] ?? '') ?? 0,
      activeConnections: int.tryParse(map['active_conn'] ?? '') ?? 0,
      createdAt: created,
      isTrial: map['is_trial'] == '1',
    );
  }
}
