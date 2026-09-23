import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around flutter_local_notifications for the agent's
/// `setReminder` tool. Reminders are scheduled with INEXACT alarms so
/// we don't need the Android 14 exact-alarm permission — a few minutes'
/// slack is fine for "your match is starting" nudges.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> _ensureInit() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _inited = true;
  }

  Future<bool> requestPermission() async {
    try {
      await _ensureInit();
      if (Platform.isAndroid) {
        final a = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return (await a?.requestNotificationsPermission()) ?? true;
      }
      if (Platform.isIOS) {
        final i = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return (await i?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            )) ??
            false;
      }
    } catch (_) {}
    return false;
  }

  /// Schedule a one-shot reminder. Returns false on non-mobile, a
  /// past time, or a platform error.
  Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required int whenEpochMs,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    if (!await requestPermission()) return false;
    final when = tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(whenEpochMs),
      tz.UTC,
    );
    if (!when.isAfter(tz.TZDateTime.now(tz.UTC))) return false;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Content reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.zonedSchedule(
        id & 0x7fffffff,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[notif] schedule failed: $e');
      return false;
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
