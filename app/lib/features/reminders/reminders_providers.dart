import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'flutter_notification_adapter.dart';
import 'notification_reminder_scheduler.dart';
import 'reminder_grouping.dart';
import 'reminder_scheduler.dart';

/// The seam tests swap. Override this with `FakeReminderScheduler` (or a
/// [NotificationReminderScheduler] built on a fake `NotificationAdapter`) inside
/// `ProviderScope(overrides: [...])`.
///
/// Production wires the real [NotificationReminderScheduler] on top of
/// [FlutterNotificationAdapter]; `main.dart` boots it and re-reconciles on every
/// app resume.
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return NotificationReminderScheduler(createNotificationAdapter());
});

/// Injectable clock so grouping + reconciliation are deterministic in tests.
final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

// --------------------------------------------------------------- raw streams

final _reminderRowsProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(remindersRepositoryProvider).watchReminders(),
);

/// Live unfired reminders grouped for the upcoming screen, each row enriched
/// with its target todo (title + due context) so the list reads offline and
/// instant. Returns [AsyncValue] so the screen can show loading / empty / data.
final upcomingRemindersProvider = Provider<AsyncValue<List<UpcomingReminder>>>((
  ref,
) {
  final remindersAsync = ref.watch(_reminderRowsProvider);
  if (remindersAsync.isLoading) {
    return const AsyncValue<List<UpcomingReminder>>.loading();
  }
  if (remindersAsync.hasError) {
    return AsyncValue<List<UpcomingReminder>>.error(
      remindersAsync.error!,
      remindersAsync.stackTrace ?? StackTrace.empty,
    );
  }

  final reminders = remindersAsync.value ?? const <Reminder>[];
  final now = ref.watch(reminderClockProvider)();
  // Todo rows carry the due context; the todos stream is watched directly so
  // this derived provider recomputes on either change and stays offline-instant.
  final todosAsync = ref.watch(_todosProvider);
  final todoIndex = <String, Todo>{
    for (final t in todosAsync.value ?? const <Todo>[]) t.uuid: t,
  };

  final rows = <UpcomingReminder>[
    for (final r in reminders)
      () {
        final todo = r.itemType.wire == 'todo' ? todoIndex[r.itemUuid] : null;
        return UpcomingReminder(
          reminder: r,
          bucket: bucketOf(r.scheduledAt, now),
          targetTitle: todo?.title ?? r.title,
          dueContext: todo?.dueAt == null ? null : _dueLabel(todo!.dueAt!, now),
        );
      }(),
  ];

  rows.sort((a, b) {
    final byBucket = _bucketRank(a.bucket).compareTo(_bucketRank(b.bucket));
    if (byBucket != 0) return byBucket;
    return a.reminder.scheduledAt.compareTo(b.reminder.scheduledAt);
  });
  return AsyncValue.data(rows);
});

final _todosProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(todosRepositoryProvider).watchTodos(),
);

String _dueLabel(DateTime due, DateTime now) => _dueWords(due, now);

/// Indonesian due label, mirroring `DsTime.dueLabel` semantics but in the
/// product's language (contract §5: writing stays in Indonesian).
String _dueWords(DateTime due, DateTime now) {
  final d = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = d.difference(today).inDays;
  if (days == 0) return 'jatuh tempo hari ini';
  if (days == 1) return 'jatuh tempo besok';
  if (days == -1) return 'terlambat sehari';
  if (days < 0) return 'terlambat ${-days}h';
  return 'jatuh tempo $days hari lagi';
}

/// Display rank for the bucket order: hari ini, besok, nanti, tertunda.
int _bucketRank(ReminderBucket bucket) => switch (bucket) {
  ReminderBucket.hariIni => 0,
  ReminderBucket.besok => 1,
  ReminderBucket.nanti => 2,
  ReminderBucket.tertunda => 3,
};
