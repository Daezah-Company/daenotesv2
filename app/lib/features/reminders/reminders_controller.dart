import 'dart:async';

import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/data/repos/reminders_repository.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminder_grouping.dart';
import 'reminder_reconciler.dart';
import 'reminder_scheduler.dart';
import 'reminders_providers.dart';

/// Everything the reminders surface can do. All writes go through the
/// repositories (which queue to the sync outbox — never HTTP from here, per
/// contract §6), and every mutation keeps the notification scheduler in step so
/// the platform and the local rows never drift.
class ReminderActions {
  ReminderActions({
    required this.reminders,
    required this.todos,
    required this.scheduler,
    required this.clock,
  });

  final RemindersRepository reminders;
  final TodosRepository todos;
  final ReminderScheduler scheduler;
  final DateTime Function() clock;

  DateTime get _now => clock();

  /// A reminder that was just cancelled, kept so the user can undo it in the
  /// same session (undo re-creates the row + notification).
  CancelledReminder? lastCancelled;

  // ---------------------------------------------------------------- schedule

  /// Create a reminder for a todo at [when] (local wall-clock) and arm the
  /// notification. Returns the new reminder uuid.
  ///
  /// A todo carries at most one live reminder: picking a second time replaces
  /// the first (row + notification) instead of stacking a duplicate buzz.
  Future<String> scheduleForTodo({
    required String todoUuid,
    required String title,
    required DateTime when,
  }) async {
    final live = await reminders.watchReminders().first;
    for (final r in live.where(
      (r) => r.itemType == DaeItemType.todo && r.itemUuid == todoUuid,
    )) {
      await reminders.cancel(r.uuid);
      await scheduler.cancel(r.uuid);
    }
    final uuid = await reminders.schedule(
      itemType: DaeItemType.todo,
      itemUuid: todoUuid,
      title: title,
      scheduledAt: when,
    );
    await todos.update(todoUuid, remindAt: Value(when));
    await scheduler.schedule(
      id: uuid,
      title: title,
      body: _bodyFor(title),
      when: when,
    );
    return uuid;
  }

  // ------------------------------------------------------------------ snooze

  /// Move [reminderUuid] to the next slot in the fixed snooze ladder, keeping
  /// the repository row and the platform notification in lock-step.
  ///
  /// There is no in-place reschedule on the repository (its api is
  /// schedule/fire/cancel), so a snooze is: cancel the old row + notification,
  /// then schedule a fresh one for the same item at the new time. The net state
  /// is exactly one live reminder and one pending notification at the snoozed
  /// time — verified by `snooze_test.dart`. Returns the new uuid, or null when
  /// the reminder no longer exists.
  Future<String?> snooze(String reminderUuid, SnoozeStep step) async {
    final row = await reminders.byUuid(reminderUuid);
    if (row == null) return null;
    final newWhen = resolveSnooze(step, _now);

    await reminders.cancel(reminderUuid);
    await scheduler.cancel(reminderUuid);

    final newUuid = await reminders.schedule(
      itemType: row.itemType,
      itemUuid: row.itemUuid,
      title: row.title,
      scheduledAt: newWhen,
    );
    if (row.itemType == DaeItemType.todo) {
      await todos.update(row.itemUuid, remindAt: Value(newWhen));
    }
    await scheduler.schedule(
      id: newUuid,
      title: row.title,
      body: _bodyFor(row.title),
      when: newWhen,
    );
    return newUuid;
  }

  // -------------------------------------------------------------- mark done

  /// Acknowledge the reminder as handled: `fire` the row and pull the pending
  /// notification. Overdue items reach here when the user taps "selesai".
  Future<void> markDone(String reminderUuid) async {
    await reminders.fire(reminderUuid);
    await scheduler.cancel(reminderUuid);
  }

  // ------------------------------------------------------------------ cancel

  /// Soft-delete a reminder and cancel its notification, remembering it so the
  /// UI can offer a one-shot undo within the session.
  Future<void> cancelReminder(String reminderUuid) async {
    final row = await reminders.byUuid(reminderUuid);
    if (row == null) return;
    lastCancelled = CancelledReminder(
      itemType: row.itemType,
      itemUuid: row.itemUuid,
      title: row.title,
      scheduledAt: row.scheduledAt,
    );
    await reminders.cancel(reminderUuid);
    await scheduler.cancel(reminderUuid);
  }

  /// Undo the most recent [cancelReminder] by re-creating the row (and its
  /// notification, if the original time is still in the future). Returns the new
  /// uuid, or null when there is nothing to undo.
  Future<String?> undoCancel() async {
    final rec = lastCancelled;
    if (rec == null) return null;
    lastCancelled = null;

    final uuid = await reminders.schedule(
      itemType: rec.itemType,
      itemUuid: rec.itemUuid,
      title: rec.title,
      scheduledAt: rec.scheduledAt,
    );
    if (rec.itemType == DaeItemType.todo) {
      await todos.update(rec.itemUuid, remindAt: Value(rec.scheduledAt));
    }
    // Re-arm only if still in the future; a past reminder returns to the list
    // as overdue rather than buzzing.
    await scheduler.schedule(
      id: uuid,
      title: rec.title,
      body: _bodyFor(rec.title),
      when: rec.scheduledAt,
    );
    return uuid;
  }

  // --------------------------------------------------------------- reconcile

  /// Bring the platform schedule in line with the local rows. Call on app
  /// resume; safe to run repeatedly (idempotent — see [reconcileReminders]).
  Future<ReconcileReport> reconcile() async {
    final rows = await reminders.watchReminders().first;
    return reconcileReminders(
      reminders: rows,
      scheduler: scheduler,
      now: _now,
      bodyOf: (r) => _bodyFor(r.title),
    );
  }

  /// Subscribe to delivered notifications and mark the matching row fired.
  /// Returns the subscription; the provider disposes it.
  StreamSubscription<String> attachFireListener() {
    return scheduler.fired.listen((uuid) => reminders.fire(uuid));
  }

  String _bodyFor(String title) => title;
}

/// Snapshot needed to re-create a reminder the user just cancelled.
class CancelledReminder {
  const CancelledReminder({
    required this.itemType,
    required this.itemUuid,
    required this.title,
    required this.scheduledAt,
  });

  final DaeItemType itemType;
  final String itemUuid;
  final String title;
  final DateTime scheduledAt;
}

/// Wires [ReminderActions] from the composition root and starts the fired
/// listener for the app's lifetime. Override `reminderSchedulerProvider` in
/// tests to inject a fake.
final reminderActionsProvider = Provider<ReminderActions>((ref) {
  final actions = ReminderActions(
    reminders: ref.watch(remindersRepositoryProvider),
    todos: ref.watch(todosRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    clock: ref.watch(reminderClockProvider),
  );
  final sub = actions.attachFireListener();
  ref.onDispose(sub.cancel);
  return actions;
});
