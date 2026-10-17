import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/features/reminders/fake_reminder_scheduler.dart';
import 'package:daenotes/features/reminders/notification_adapter.dart';
import 'package:daenotes/features/reminders/notification_reminder_scheduler.dart';
import 'package:daenotes/features/reminders/reminder_reconciler.dart';
import 'package:daenotes/features/reminders/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plugin-free [NotificationAdapter] double so the real
/// [NotificationReminderScheduler] is testable without `flutter_local_notifications`.
class _RecordingAdapter implements NotificationAdapter {
  final Map<String, DateTime> scheduled = {};
  final List<String> log = [];
  bool initCalled = false;

  @override
  Future<void> init() async => initCalled = true;

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    scheduled[id] = when;
    log.add('schedule:$id');
  }

  @override
  Future<void> cancel(String id) async {
    scheduled.remove(id);
    log.add('cancel:$id');
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    log.add('cancelAll');
  }

  @override
  Future<Set<String>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Stream<String> get fired => const Stream<String>.empty();
}

Reminder row({
  required String uuid,
  required DateTime scheduledAt,
  DateTime? firedAt,
  DateTime? deletedAt,
  String title = 'Pengingat',
}) => Reminder(
  id: 0,
  uuid: uuid,
  itemType: DaeItemType.note,
  itemUuid: 'item-$uuid',
  scheduledAt: scheduledAt,
  title: title,
  firedAt: firedAt,
  deletedAt: deletedAt,
  updatedAt: scheduledAt,
);

void main() {
  final now = DateTime(2026, 10, 18, 9, 0);
  DateTime future(int h) => now.add(Duration(hours: h));

  // Run the whole suite against BOTH scheduler implementations so the fake and
  // the real one behave identically (the real one only via its plugin-free
  // [NotificationReminderScheduler] guard + recording adapter).
  final factories = <String, ReminderScheduler Function()>{
    'FakeReminderScheduler': () => FakeReminderScheduler(clock: () => now),
    'NotificationReminderScheduler + recording adapter': () =>
        NotificationReminderScheduler(_RecordingAdapter(), clock: () => now),
  };

  for (final entry in factories.entries) {
    final label = entry.key;
    final makeScheduler = entry.value;
    group('reconcile via $label', () {
      test('creates a notification for each active, future reminder', () async {
        final scheduler = makeScheduler();
        final reminders = [
          row(uuid: 'a', scheduledAt: future(2)),
          row(uuid: 'b', scheduledAt: future(26)),
        ];

        final report = await reconcileReminders(
          reminders: reminders,
          scheduler: scheduler,
          now: now,
        );

        expect(report.created, unorderedEquals(['a', 'b']));
        expect(
          (await scheduler.scheduledSnapshot()).keys,
          unorderedEquals(['a', 'b']),
        );
      });

      test(
        'is idempotent: a second run with unchanged rows is a no-op',
        () async {
          final scheduler = makeScheduler();
          final reminders = [
            row(uuid: 'a', scheduledAt: future(2)),
            row(uuid: 'b', scheduledAt: future(26)),
          ];

          final first = await reconcileReminders(
            reminders: reminders,
            scheduler: scheduler,
            now: now,
          );
          expect(first.created, hasLength(2));

          final second = await reconcileReminders(
            reminders: reminders,
            scheduler: scheduler,
            now: now,
          );
          expect(second.isNoop, isTrue, reason: 'nothing should move');
          expect(second.unchanged, unorderedEquals(['a', 'b']));

          // A third run, same.
          final third = await reconcileReminders(
            reminders: reminders,
            scheduler: scheduler,
            now: now,
          );
          expect(third.isNoop, isTrue);
        },
      );

      test('cancels a notification whose row was just fired', () async {
        final scheduler = makeScheduler();
        // Pre-arm so the scheduler holds 'a', then the row comes back fired.
        await scheduler.schedule(
          id: 'a',
          title: 'a',
          body: 'a',
          when: future(2),
        );

        final report = await reconcileReminders(
          reminders: [row(uuid: 'a', scheduledAt: future(2), firedAt: now)],
          scheduler: scheduler,
          now: now,
        );

        expect(report.cancelled, contains('a'));
        expect(await scheduler.scheduledSnapshot(), isEmpty);
      });

      test('cancels a notification whose row was deleted', () async {
        final scheduler = makeScheduler();
        await scheduler.schedule(
          id: 'x',
          title: 'x',
          body: 'x',
          when: future(3),
        );

        final report = await reconcileReminders(
          // Row list reflects the live stream: deleted rows are absent.
          reminders: const [],
          scheduler: scheduler,
          now: now,
        );

        expect(report.cancelled, contains('x'));
        expect(await scheduler.scheduledSnapshot(), isEmpty);
      });

      test('reschedules a reminder whose time moved', () async {
        final scheduler = makeScheduler();
        // First pass arms 'a' at 11:00.
        await reconcileReminders(
          reminders: [row(uuid: 'a', scheduledAt: future(2))],
          scheduler: scheduler,
          now: now,
        );

        // The row moves to 15:00 (snooze / edited remind_at).
        final report = await reconcileReminders(
          reminders: [row(uuid: 'a', scheduledAt: future(6))],
          scheduler: scheduler,
          now: now,
        );

        expect(report.rescheduled, contains('a'));
        expect((await scheduler.scheduledSnapshot())['a'], future(6));

        // And now it is stable again.
        final after = await reconcileReminders(
          reminders: [row(uuid: 'a', scheduledAt: future(6))],
          scheduler: scheduler,
          now: now,
        );
        expect(after.isNoop, isTrue);
      });

      test('overdue rows are never armed — no launch burst', () async {
        final scheduler = makeScheduler();
        final report = await reconcileReminders(
          reminders: [
            row(
              uuid: 'late1',
              scheduledAt: now.subtract(const Duration(hours: 3)),
            ),
            row(
              uuid: 'late2',
              scheduledAt: now.subtract(const Duration(days: 1)),
            ),
          ],
          scheduler: scheduler,
          now: now,
        );

        expect(report.created, isEmpty);
        expect(await scheduler.scheduledSnapshot(), isEmpty);
      });

      test(
        'a lingering notification for a now-past reminder is cleared',
        () async {
          final scheduler = makeScheduler();
          // Armed earlier for a time that has since passed.
          await scheduler.schedule(
            id: 'due',
            title: 'due',
            body: 'due',
            when: now.add(const Duration(hours: 1)),
          );

          final report = await reconcileReminders(
            reminders: [
              row(
                uuid: 'due',
                scheduledAt: now.subtract(const Duration(minutes: 5)),
              ),
            ],
            scheduler: scheduler,
            now: now,
          );

          expect(report.cancelled, contains('due'));
          expect(await scheduler.scheduledSnapshot(), isEmpty);
        },
      );
    });
  }
}
