import 'dart:async';

import 'notification_adapter.dart';
import 'reminder_scheduler.dart';

/// The production [ReminderScheduler]: it owns the reminder-domain rules (the
/// past-time guard and the in-memory mirror of what's pending) and delegates
/// every platform call to a [NotificationAdapter], which is the one file that
/// knows about `flutter_local_notifications`.
///
/// Keeping the mirror here (not on the adapter) means the reconciler can diff
/// cheaply and [scheduledSnapshot] never needs a round-trip that a disabled
/// adapter can't answer. On a cold process the mirror starts empty; the
/// reconciler repopulates it from the drift rows, and any orphan notification
/// the platform still holds is cleared via [NotificationAdapter.scheduledIds].
class NotificationReminderScheduler implements ReminderScheduler {
  NotificationReminderScheduler(this._adapter, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final NotificationAdapter _adapter;
  final DateTime Function() _clock;
  final Map<String, DateTime> _mirror = {};

  DateTime get _now => _clock();

  @override
  Future<void> init() async {
    await _adapter.init();
    _mirror.clear();
    // On a cold start we adopt the ids the platform reports (without times —
    // reconciliation repopulates times from the drift rows and re-arms in the
    // same pass), so the mirror never under-reports a still-pending id.
    for (final id in await _adapter.scheduledIds()) {
      _mirror.putIfAbsent(id, () => _now);
    }
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    // Wall-clock contract: an already-past time must not buzz on launch. The
    // row stays in drift and surfaces in the "Tertunda" group instead. Any
    // stale notification for it is cleared so nothing fires late.
    if (!when.isAfter(_now)) {
      _mirror.remove(id);
      await _adapter.cancel(id);
      return;
    }
    _mirror[id] = when;
    await _adapter.schedule(id: id, title: title, body: body, when: when);
  }

  @override
  Future<void> cancel(String id) async {
    _mirror.remove(id);
    await _adapter.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    _mirror.clear();
    await _adapter.cancelAll();
  }

  @override
  Future<Map<String, DateTime>> scheduledSnapshot() async => Map.of(_mirror);

  @override
  Stream<String> get fired => _adapter.fired;
}
