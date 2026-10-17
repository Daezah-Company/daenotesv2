import 'dart:async';

/// The narrow plugin seam the reminders feature sits on. Everything above this
/// is pure Dart and testable with [FakeReminderScheduler]; only the concrete
/// implementation in `flutter_notification_adapter.dart` touches
/// `flutter_local_notifications` / `timezone`.
///
/// The adapter speaks in **reminder uuids** and **local wall-clock** times —
/// it is the adapter's job to map a uuid onto a platform notification id and a
/// local `DateTime` onto a DST-correct scheduled delivery (see
/// `FlutterNotificationAdapter.init` note on `tz.setLocalLocation`).
abstract interface class NotificationAdapter {
  Future<void> init();

  /// Deliver at the local wall-clock [when]. Implementations MUST interpret the
  /// fields as wall-clock (a due time of 18:00 stays 18:00 across DST), and MUST
  /// not deliver a time that is already in the past.
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  });

  Future<void> cancel(String id);

  Future<void> cancelAll();

  /// Ids of everything currently awaiting delivery on the platform.
  Future<Set<String>> scheduledIds();

  /// Emits a reminder uuid when its notification is tapped/delivered.
  Stream<String> get fired;
}
