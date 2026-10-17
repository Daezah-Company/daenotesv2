/// The notification seam for the reminders feature.
///
/// The app schedules *wall-clock local* reminders (contract §6: jadwal lokal
/// dari `remind_at`). Everything above this interface is timezone- and
/// plugin-agnostic and fully unit-testable; the only thing that knows about
/// `flutter_local_notifications` / `timezone` is [ReminderNotifier], which is
/// wired in `notification_adapter.dart`.
///
/// `id` is always a reminder row's **uuid** (contract §3: uuid is the client
/// idempotency key) so the same reminder maps to the same native notification
/// across reschedules — calling [schedule] twice with the same `id` replaces,
/// never duplicates.
abstract interface class ReminderScheduler {
  /// Initialise the backing notifier. Safe to call more than once.
  Future<void> init();

  /// Schedule (or replace) a notification for [when], a local wall-clock time.
  ///
  /// Implementations must NOT fire a notification whose [when] is already in
  /// the past at call time — an overdue reminder surfaces in the list instead
  /// of buzzing on launch (see [NotificationReminderScheduler]'s guard).
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  });

  /// Cancel the notification for [id]. A no-op when nothing is pending.
  Future<void> cancel(String id);

  /// Cancel every pending notification this app scheduled.
  Future<void> cancelAll();

  /// The ids and wall-clock times of everything currently scheduled for
  /// delivery: reminder uuid -> local time. The reconciler diffs this against
  /// the local reminder rows to decide what to create / cancel / reschedule, so
  /// the whole routine stays idempotent. After a cold restart a live scheduler
  /// may return an empty map (the platform cannot report per-item times); the
  /// reconciler then re-arms every active future row, which is safe because a
  /// re-schedule simply replaces the matching notification.
  Future<Map<String, DateTime>> scheduledSnapshot();

  /// Emits the uuid of a reminder as its notification is delivered.
  /// Consumers mark the matching row fired via `RemindersRepository.fire`.
  Stream<String> get fired;
}
