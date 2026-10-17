import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/reminders_repository.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:daenotes/features/reminders/fake_reminder_scheduler.dart';
import 'package:daenotes/features/reminders/reminder_grouping.dart';
import 'package:daenotes/features/reminders/reminders_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9, 0);

  late AppDatabase db;
  late Outbox outbox;
  late RemindersRepository reminders;
  late TodosRepository todos;
  late FakeReminderScheduler scheduler;
  late ReminderActions actions;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    reminders = RemindersRepository(db, outbox);
    todos = TodosRepository(db, outbox);
    scheduler = FakeReminderScheduler(clock: () => now);
    actions = ReminderActions(
      reminders: reminders,
      todos: todos,
      scheduler: scheduler,
      clock: () => now,
    );
  });

  tearDown(() async {
    await scheduler.dispose();
    await db.close();
  });

  group('schedule for a todo', () {
    test(
      're-picking a time replaces the live reminder instead of stacking',
      () async {
        final todoUuid = await todos.create(title: 'Ambil obat', dueAt: now);
        final first = await actions.scheduleForTodo(
          todoUuid: todoUuid,
          title: 'Ambil obat',
          when: now.add(const Duration(hours: 1)),
        );
        final second = await actions.scheduleForTodo(
          todoUuid: todoUuid,
          title: 'Ambil obat',
          when: now.add(const Duration(hours: 3)),
        );

        expect(second, isNot(first));
        // The old buzz is gone from both surfaces: soft-deleted row, no
        // pending notification, so one todo can never fire twice.
        expect(scheduler.scheduled.keys, [second]);
        expect((await reminders.byUuid(first))?.deletedAt, isNotNull);
        final live = await reminders.watchReminders().first;
        expect(live.map((r) => r.uuid), [second]);
        expect((await todos.byUuid(todoUuid))?.remindAt, isNotNull);
      },
    );
  });

  group('snooze', () {
    test('moves the notification and the repository row together', () async {
      final todoUuid = await todos.create(title: 'Ambil obat', dueAt: now);
      final firstWhen = now.add(const Duration(hours: 2));
      final uuid = await actions.scheduleForTodo(
        todoUuid: todoUuid,
        title: 'Ambil obat',
        when: firstWhen,
      );

      // Precondition: one live row, one pending notification, both at firstWhen.
      expect(scheduler.scheduled[uuid], firstWhen);
      expect(await reminders.watchReminders().first, hasLength(1));

      final newUuid = await actions.snooze(uuid, SnoozeStep.satuJam);
      final expected = now.add(const Duration(hours: 1));

      // Notification moved to the new slot under the new row id; the old one is
      // gone from the platform schedule.
      expect(scheduler.scheduled, hasLength(1));
      expect(scheduler.scheduled[newUuid], expected);
      expect(scheduler.scheduled.containsKey(uuid), isFalse);

      // Repository moved in lock-step: exactly one live reminder at the new time.
      final live = await reminders.watchReminders().first;
      expect(live, hasLength(1));
      expect(live.single.uuid, newUuid);
      expect(live.single.scheduledAt, expected);
      expect(live.single.itemUuid, todoUuid);

      // The old row is soft-deleted (tombstone), not physically dropped, so the
      // outbox can propagate the deletion on next sync.
      final oldRow = await reminders.byUuid(uuid);
      expect(oldRow?.deletedAt, isNotNull);

      // The todo's own remind_at followed it.
      final todo = await todos.byUuid(todoUuid);
      expect(todo?.remindAt, expected);
    });

    test('besok pagi snooze lands on the next 07:00 wall-clock', () async {
      final uuid = await actions.scheduleForTodo(
        todoUuid: 't1',
        title: 'Rapat',
        when: now.add(const Duration(hours: 3)),
      );
      final newUuid = await actions.snooze(uuid, SnoozeStep.besokPagi);
      final expected = DateTime(2026, 10, 19, 7, 0);
      expect(scheduler.scheduled[newUuid], expected);
      // Wall-clock preserved: hour stays 07 regardless of any UTC offset.
      expect(scheduler.scheduled[newUuid]!.hour, 7);
    });

    test('nanti malam targets tonight 20:00 while it is still ahead', () async {
      final uuid = await actions.scheduleForTodo(
        todoUuid: 't2',
        title: 'Laporan',
        when: now.add(const Duration(hours: 1)),
      );
      final newUuid = await actions.snooze(uuid, SnoozeStep.nantiMalam);
      // 09:00 -> tonight 20:00 is still ahead, so it stays today.
      expect(scheduler.scheduled[newUuid], DateTime(2026, 10, 18, 20, 0));
    });
  });

  group('mark done', () {
    test('fires the row and cancels its notification', () async {
      final uuid = await actions.scheduleForTodo(
        todoUuid: 't3',
        title: 'Bayar',
        when: now.add(const Duration(hours: 4)),
      );
      expect(scheduler.scheduled, contains(uuid));

      await actions.markDone(uuid);

      expect(scheduler.scheduled, isEmpty);
      expect(await reminders.watchReminders().first, isEmpty);
      final row = await reminders.byUuid(uuid);
      expect(row?.firedAt, isNotNull);
    });
  });

  group('cancel + undo', () {
    test('cancel removes it, undo restores it within the session', () async {
      final when = now.add(const Duration(hours: 5));
      final uuid = await actions.scheduleForTodo(
        todoUuid: 't4',
        title: 'Telepon bank',
        when: when,
      );

      await actions.cancelReminder(uuid);
      expect(scheduler.scheduled, isEmpty);
      expect(await reminders.watchReminders().first, isEmpty);

      final restored = await actions.undoCancel();
      expect(restored, isNotNull);
      expect(await reminders.watchReminders().first, hasLength(1));
      expect((await reminders.watchReminders().first).single.scheduledAt, when);
      expect(scheduler.scheduled, contains(restored));
    });

    test(
      'undo of a now-past reminder returns it to the list, not the buzzer',
      () async {
        var clock = now;
        final sch = FakeReminderScheduler(clock: () => clock);
        final a = ReminderActions(
          reminders: reminders,
          todos: todos,
          scheduler: sch,
          clock: () => clock,
        );

        final when = now.add(const Duration(hours: 5));
        final uuid = await a.scheduleForTodo(
          todoUuid: 't5',
          title: 'Telat',
          when: when,
        );
        expect(sch.scheduled, contains(uuid));

        await a.cancelReminder(uuid);
        // Advance the real clock so the captured `when` is now in the past.
        clock = when.add(const Duration(minutes: 1));

        final restored = await a.undoCancel();
        expect(restored, isNotNull);
        // Row is back in the live list (as overdue)...
        final live = await reminders.watchReminders().first;
        expect(live, hasLength(1));
        expect(live.single.scheduledAt, when);
        // ...but no notification is armed for a past time.
        expect(sch.scheduled, isEmpty);
      },
    );
  });

  group('reconcile on resume', () {
    test(
      'overdue rows do not create notifications (no launch burst)',
      () async {
        // Two overdue reminders sitting in drift (unfired, not deleted).
        await db
            .into(db.reminders)
            .insert(
              RemindersCompanion.insert(
                uuid: 'late-1',
                itemType: DaeItemType.note,
                itemUuid: 'n1',
                scheduledAt: now.subtract(const Duration(days: 1)),
                title: const Value('Salah waktu'),
                updatedAt: now,
              ),
            );
        await db
            .into(db.reminders)
            .insert(
              RemindersCompanion.insert(
                uuid: 'late-2',
                itemType: DaeItemType.note,
                itemUuid: 'n2',
                scheduledAt: now.subtract(const Duration(hours: 2)),
                title: const Value('Lewat'),
                updatedAt: now,
              ),
            );

        final report = await actions.reconcile();

        expect(report.created, isEmpty);
        expect(scheduler.scheduled, isEmpty);
      },
    );

    test('reconcile arms pending future rows and is idempotent', () async {
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              uuid: 'soon',
              itemType: DaeItemType.note,
              itemUuid: 'n3',
              scheduledAt: now.add(const Duration(hours: 3)),
              title: const Value('Nanti'),
              updatedAt: now,
            ),
          );

      final first = await actions.reconcile();
      expect(first.created, contains('soon'));

      final second = await actions.reconcile();
      expect(second.isNoop, isTrue);
      expect(scheduler.scheduled.keys, contains('soon'));
    });
  });
}
