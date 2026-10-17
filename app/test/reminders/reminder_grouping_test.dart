import 'package:daenotes/features/reminders/reminder_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bucketOf (wall-clock local buckets)', () {
    final now = DateTime(2026, 10, 18, 9, 0);

    test('future time today is hari ini', () {
      expect(
        bucketOf(DateTime(2026, 10, 18, 18, 0), now),
        ReminderBucket.hariIni,
      );
    });

    test('anything before now is tertunda, even late in today', () {
      expect(
        bucketOf(DateTime(2026, 10, 18, 8, 59), now),
        ReminderBucket.tertunda,
      );
      expect(
        bucketOf(DateTime(2026, 10, 10, 23, 0), now),
        ReminderBucket.tertunda,
      );
    });

    test('tomorrow calendar day is besok regardless of the hour', () {
      expect(bucketOf(DateTime(2026, 10, 19, 0, 5), now), ReminderBucket.besok);
      expect(
        bucketOf(DateTime(2026, 10, 19, 23, 0), now),
        ReminderBucket.besok,
      );
    });

    test('beyond tomorrow is nanti', () {
      expect(bucketOf(DateTime(2026, 10, 20, 7, 0), now), ReminderBucket.nanti);
      expect(bucketOf(DateTime(2026, 12, 1, 7, 0), now), ReminderBucket.nanti);
    });
  });

  group('resolveSnooze keeps wall-clock semantics', () {
    test('satu jam adds exactly one hour', () {
      final r = resolveSnooze(
        SnoozeStep.satuJam,
        DateTime(2026, 10, 18, 9, 30),
      );
      expect(r, DateTime(2026, 10, 18, 10, 30));
    });

    test('nanti malam targets 20:00 same day while it is ahead', () {
      final r = resolveSnooze(
        SnoozeStep.nantiMalam,
        DateTime(2026, 10, 18, 12, 0),
      );
      expect(r.hour, 20);
      expect(r.day, 18);
    });

    test('nanti malam rolls to tomorrow after 20:00', () {
      final r = resolveSnooze(
        SnoozeStep.nantiMalam,
        DateTime(2026, 10, 18, 21, 0),
      );
      expect(r, DateTime(2026, 10, 19, 20, 0));
    });

    test('besok pagi is tomorrow 07:00, wall-clock hour preserved', () {
      final r = resolveSnooze(
        SnoozeStep.besokPagi,
        DateTime(2026, 10, 18, 23, 30),
      );
      expect(r, DateTime(2026, 10, 19, 7, 0));
      expect(r.hour, 7);
    });
  });

  test('a 18:00 reminder stays 18:00 across a DST-ish date boundary', () {
    // We never convert to UTC on the scheduling path, so the hour fields are
    // exactly what the user set, independent of the running zone's offset.
    final sixPm = DateTime(2026, 3, 29, 18, 0); // Northern-hemisphere DST night
    final resolved = resolveSnooze(SnoozeStep.satuJam, sixPm);
    expect(resolved.hour, 19); // 18:00 -> 19:00 wall-clock, no UTC normalise
    expect(resolved.minute, 0);
    expect(resolved.day, 29);
    final bucket = bucketOf(sixPm, DateTime(2026, 3, 29, 9, 0));
    expect(bucket, ReminderBucket.hariIni);
    expect(sixPm.hour, 18);
  });
}
