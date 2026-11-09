import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_adapter.dart';

/// Adapter over `flutter_local_notifications`.
///
/// Identity: the reminder **uuid** is carried in the notification `payload`, so
/// a tap resolves back to the row without an in-process id map, and pending
/// notifications are recognised by payload after a cold restart. The platform
/// int id is derived from the uuid by a stable FNV-1a hash — Dart's
/// `String.hashCode` is not documented as stable across processes, so it is
/// deliberately not used.
///
/// Timing: `when` is the local wall-clock read of the drift row. It is turned
/// into the exact instant the user meant via `DateTime.toUtc()`, which applies
/// the device's *current* offset. That is correct for fixed-offset zones
/// (WIB/WITA/WIT) and for reminders that do not straddle a DST change; true
/// wall-clock scheduling across a future DST boundary would need a named zone
/// (e.g. `flutter_timezone`), which this app does not ship.
class FlutterNotificationAdapter implements NotificationAdapter {
  FlutterNotificationAdapter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _fired = StreamController<String>.broadcast();

  static const _channelId = 'daenotes_pengingat';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Pengingat',
      channelDescription: 'Pengingat untuk catatan dan todo',
      icon: 'daenotes_notification',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings(
          'daenotes_notification',
        ),
        iOS: const DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      // `exactAllowWhileIdle` needs this on Android 12+; declined permission
      // falls back to inexact delivery, so it is asked for, never required.
      await android?.requestExactAlarmsPermission();
    }
  }

  void _onResponse(NotificationResponse response) {
    final uuid = response.payload;
    if (uuid != null && uuid.isNotEmpty) _fired.add(uuid);
  }

  static int pluginIdFor(String uuid) {
    var hash = 0x811c9dc5;
    for (final unit in uuid.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final target = tz.TZDateTime.from(when.toUtc(), tz.local);
    if (!target.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: pluginIdFor(id),
      title: title,
      body: body,
      payload: id,
      scheduledDate: target,
      notificationDetails: _details,
      // Exact alarms are a grant, not a guarantee: asking without `SCHEDULE_
      // EXACT_ALARM` being approved throws on Android 12+, so a declined user
      // falls back to "roughly at that time" instead of losing the reminder.
      androidScheduleMode: await _scheduleMode(),
    );
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;
    final exact = await android.canScheduleExactNotifications() ?? false;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  @override
  Future<void> cancel(String id) => _plugin.cancel(id: pluginIdFor(id));

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<Set<String>> scheduledIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    final ids = <String>{};
    for (final request in pending) {
      final uuid = request.payload;
      if (uuid != null && uuid.isNotEmpty) ids.add(uuid);
    }
    return ids;
  }

  @override
  Stream<String> get fired => _fired.stream;
}

/// Factory the [NotificationReminderScheduler] is built on.
NotificationAdapter createNotificationAdapter() => FlutterNotificationAdapter();
