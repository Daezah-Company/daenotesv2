import 'package:daenotes/data/db/database.dart';

/// The four buckets the upcoming screen groups reminders into, in display
/// order. `tertunda` (overdue) is rendered last, as an invitation to clean up —
/// never as an alarm.
enum ReminderBucket { hariIni, besok, nanti, tertunda }

/// A reminder paired with the resolved target item, ready for a list row.
class UpcomingReminder {
  const UpcomingReminder({
    required this.reminder,
    required this.bucket,
    this.targetTitle,
    this.dueContext,
  });

  final Reminder reminder;
  final ReminderBucket bucket;

  /// Title of the note/todo this reminder points at (resolved from drift), or
  /// null when the target was deleted server-side before we synced.
  final String? targetTitle;

  /// For a todo, its due date as a short wall-clock label (`today`, `besok`,
  /// `Mon 4`); null for notes or when there is no due date.
  final String? dueContext;
}

/// Pure local-calendar day index: midnight-to-midnight in the device's zone.
/// Uses only the Y/M/D fields of the [DateTime]s, which for a local `DateTime`
/// means the *wall-clock* day — so a `18:00` reminder stays in the day its
/// fields say, across a DST shift.
int _dayIndex(DateTime t) =>
    DateTime(t.year, t.month, t.day).millisecondsSinceEpoch;

/// Classify a scheduled wall-clock time relative to `now` into a bucket.
ReminderBucket bucketOf(DateTime scheduledAt, DateTime now) {
  if (scheduledAt.isBefore(now)) return ReminderBucket.tertunda;
  final days =
      (_dayIndex(scheduledAt) - _dayIndex(now)) ~/ Duration.millisecondsPerDay;
  if (days <= 0) return ReminderBucket.hariIni;
  if (days == 1) return ReminderBucket.besok;
  return ReminderBucket.nanti;
}

/// Fixed, sensible snooze ladder — a small set, not a free datetime picker.
enum SnoozeStep { satuJam, nantiMalam, besokPagi }

SnoozeStep? snoozeStepFromName(String name) =>
    SnoozeStep.values.where((s) => s.name == name).firstOrNull;

/// Resolve a snooze step to the next appropriate *local wall-clock* instant
/// strictly after `from`. Labels stay in Indonesian (contract §5 writing).
DateTime resolveSnooze(SnoozeStep step, DateTime from) {
  switch (step) {
    case SnoozeStep.satuJam:
      return from.add(const Duration(hours: 1));
    case SnoozeStep.nantiMalam:
      // Later tonight at 20:00, else tomorrow 20:00 if tonight already passed.
      final tonight = DateTime(from.year, from.month, from.day, 20, 0);
      if (tonight.isAfter(from)) return tonight;
      return tonight.add(const Duration(days: 1));
    case SnoozeStep.besokPagi:
      // Next 07:00 strictly after `from`.
      final tomorrowMorning = DateTime(
        from.year,
        from.month,
        from.day,
        7,
        0,
      ).add(const Duration(days: 1));
      return tomorrowMorning;
  }
}

/// Human labels for the ladder, matching the product voice.
String snoozeStepLabel(SnoozeStep step) => switch (step) {
  SnoozeStep.satuJam => '1 jam',
  SnoozeStep.nantiMalam => 'nanti malam',
  SnoozeStep.besokPagi => 'besok pagi',
};

/// Bucket section titles (Indonesian, per contract writing rules).
String bucketLabel(ReminderBucket bucket) => switch (bucket) {
  ReminderBucket.hariIni => 'Hari ini',
  ReminderBucket.besok => 'Besok',
  ReminderBucket.nanti => 'Nanti',
  ReminderBucket.tertunda => 'Tertunda',
};
