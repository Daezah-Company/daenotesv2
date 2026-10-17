import 'dart:async';

import 'reminder_scheduler.dart';

/// Deterministic in-memory [ReminderScheduler]. This is what every test — and
/// the whole feature under `ProviderScope(overrides: [...])` — uses while
/// `flutter_local_notifications` is not yet a dependency.
///
/// It records calls instead of touching a plugin, keeps its own pending mirror
/// so reconciliation can be diffed, and honours the same wall-clock/past rules
/// as [NotificationReminderScheduler] so behaviour matches one for one.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// id -> scheduled wall-clock time, for everything currently "pending".
  final Map<String, DateTime> scheduled = {};

  /// Every title/body that was scheduled, keyed by id (for assertions).
  final Map<String, ({String title, String body})> payloads = {};

  final List<String> log = [];
  final StreamController<String> _fired = StreamController<String>.broadcast();

  bool initialized = false;

  DateTime get now => _clock();

  @override
  Future<void> init() async {
    initialized = true;
    log.add('init');
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    // Wall-clock contract: never buzz for a time already in the past. Overdue
    // items surface in the list, not as a launch burst.
    if (!when.isAfter(now)) {
      log.add('skip-past:$id');
      return;
    }
    scheduled[id] = when;
    payloads[id] = (title: title, body: body);
    log.add('schedule:$id');
  }

  @override
  Future<void> cancel(String id) async {
    scheduled.remove(id);
    payloads.remove(id);
    log.add('cancel:$id');
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
    payloads.clear();
    log.add('cancelAll');
  }

  @override
  Future<Map<String, DateTime>> scheduledSnapshot() async => Map.of(scheduled);

  @override
  Stream<String> get fired => _fired.stream;

  /// Test hook: pretend the OS delivered a reminder.
  void simulateFire(String id) => _fired.add(id);

  Future<void> dispose() => _fired.close();
}
