import 'package:daenotes/core/ds.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/features/reminders/fake_reminder_scheduler.dart';
import 'package:daenotes/features/reminders/reminders_providers.dart';
import 'package:daenotes/features/reminders/reminders_screen.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 18, 9, 0);

  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<AppDatabase> seed(List<({String uuid, DateTime at})> items) async {
    final db = AppDatabase(NativeDatabase.memory());
    for (final i in items) {
      await db
          .into(db.reminders)
          .insert(
            RemindersCompanion.insert(
              uuid: i.uuid,
              itemType: DaeItemType.note,
              itemUuid: 'item-${i.uuid}',
              scheduledAt: i.at,
              title: const Value('Pengingat'),
              updatedAt: now,
            ),
          );
    }
    return db;
  }

  Widget harness(AppDatabase db) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      reminderSchedulerProvider.overrideWithValue(
        FakeReminderScheduler(clock: () => now),
      ),
      reminderClockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp(theme: DsTheme.dark(), home: const RemindersScreen()),
  );

  testWidgets('empty state is an invitation, not an apology', (tester) async {
    final db = await seed(const []);
    await tester.pumpWidget(harness(db));
    await tester.pumpAndSettle();

    expect(find.text('Jadwalkan yang pertama'), findsOneWidget);
    // Points at the fastest way to schedule one (from a todo).
    expect(find.textContaining('ketuk Pengingat'), findsOneWidget);
    // No apology words.
    expect(find.textContaining('maaf'), findsNothing);
    await db.close();
  });

  testWidgets('groups reminders by wall-clock bucket, overdue last', (
    tester,
  ) async {
    final db = await seed([
      (uuid: 'later', at: now.add(const Duration(days: 3))),
      (uuid: 'today', at: now.add(const Duration(hours: 3))),
      (uuid: 'tomorrow', at: now.add(const Duration(days: 1, hours: 2))),
      (uuid: 'late', at: now.subtract(const Duration(days: 2))),
    ]);
    await tester.pumpWidget(harness(db));
    await tester.pumpAndSettle();

    // Section headers render as DsEyebrow (mono UPPERCASE).
    expect(find.text('HARI INI'), findsOneWidget);
    expect(find.text('BESOK'), findsOneWidget);
    expect(find.text('NANTI'), findsOneWidget);
    expect(find.text('TERTUNDA'), findsOneWidget);
    await db.close();
  });

  testWidgets('overdue bucket is present without any firing', (tester) async {
    final scheduler = FakeReminderScheduler(clock: () => now);
    final db = await seed([
      (uuid: 'missed', at: now.subtract(const Duration(hours: 6))),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          reminderSchedulerProvider.overrideWithValue(scheduler),
          reminderClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: DsTheme.dark(),
          home: const RemindersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TERTUNDA'), findsOneWidget);
    // The resume-reconcile the screen runs must not arm anything for the past.
    expect(scheduler.scheduled, isEmpty);
    await db.close();
  });
}
