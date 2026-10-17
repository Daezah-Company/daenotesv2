import 'package:daenotes/data/db/database.dart';

import 'reminder_scheduler.dart';

/// Outcome of one reconciliation pass — the counts of the three mutations, so
/// callers (and tests) can assert exactly what changed.
class ReconcileReport {
  const ReconcileReport({
    this.created = const [],
    this.rescheduled = const [],
    this.cancelled = const [],
    this.unchanged = const [],
  });

  final List<String> created;
  final List<String> rescheduled;
  final List<String> cancelled;
  final List<String> unchanged;

  bool get isNoop =>
      created.isEmpty && rescheduled.isEmpty && cancelled.isEmpty;

  @override
  String toString() =>
      'ReconcileReport(created: ${created.length}, '
      'rescheduled: ${rescheduled.length}, cancelled: ${cancelled.length}, '
      'unchanged: ${unchanged.length})';
}

/// Brings the platform's scheduled notifications back in line with the local
/// `reminders` rows (contract §6: jadwal lokal dari `remind_at`).
///
/// Runs on app resume and after any local write. It is **idempotent**: given the
/// same rows and the same scheduler state, a second run produces a no-op
/// report. The three effects it can have:
///
///  * created      — an active, future reminder with no notification yet
///  * rescheduled  — an active, future reminder whose stored time moved
///  * cancelled    — a notification for a reminder that is now fired, deleted,
///                   or scheduled in the past (an overdue row shows in the list
///                   instead of buzzing)
///
/// [bodyOf] lets the caller render the target-item subtitle for the
/// notification; it defaults to the reminder title.
Future<ReconcileReport> reconcileReminders({
  required List<Reminder> reminders,
  required ReminderScheduler scheduler,
  required DateTime now,
  String Function(Reminder reminder)? bodyOf,
}) async {
  final snapshot = await scheduler.scheduledSnapshot();
  final created = <String>[];
  final rescheduled = <String>[];
  final cancelled = <String>[];
  final unchanged = <String>[];

  // Only live reminders can own a notification: not deleted, not fired.
  final active = reminders.where(
    (r) => r.deletedAt == null && r.firedAt == null,
  );

  final liveUuids = <String>{};
  for (final r in active) {
    liveUuids.add(r.uuid);
    final isFuture = r.scheduledAt.isAfter(now);
    final alreadyScheduled = snapshot.containsKey(r.uuid);

    if (!isFuture) {
      // Overdue / just-fired: never arm a notification. If one somehow lingers
      // (e.g. the clock moved past it), clear it so nothing buzzs late.
      if (alreadyScheduled) {
        await scheduler.cancel(r.uuid);
        cancelled.add(r.uuid);
      }
      continue;
    }

    final existing = snapshot[r.uuid];
    if (!alreadyScheduled) {
      await scheduler.schedule(
        id: r.uuid,
        title: r.title,
        body: (bodyOf ?? (reminder) => reminder.title)(r),
        when: r.scheduledAt,
      );
      created.add(r.uuid);
    } else if (existing != r.scheduledAt) {
      // The row moved — re-arm to the new wall-clock time.
      await scheduler.schedule(
        id: r.uuid,
        title: r.title,
        body: (bodyOf ?? (reminder) => reminder.title)(r),
        when: r.scheduledAt,
      );
      rescheduled.add(r.uuid);
    } else {
      unchanged.add(r.uuid);
    }
  }

  // Anything the scheduler still holds for a reminder that is no longer live
  // (deleted or already fired) must be released.
  for (final uuid in snapshot.keys) {
    if (!liveUuids.contains(uuid)) {
      await scheduler.cancel(uuid);
      cancelled.add(uuid);
    }
  }

  return ReconcileReport(
    created: created,
    rescheduled: rescheduled,
    cancelled: cancelled,
    unchanged: unchanged,
  );
}
