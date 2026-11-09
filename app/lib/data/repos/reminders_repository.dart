import 'package:drift/drift.dart';

import '../../core/dae_types.dart';
import '../db/database.dart';
import '../model/uuid.dart';
import 'outbox.dart';

/// Reminders are scheduled locally from `remind_at` (contract §6) and synced
/// as data rows. A monochrome rail marks their status.
class RemindersRepository {
  RemindersRepository(this._db, this._outbox);

  final AppDatabase _db;
  final Outbox _outbox;

  Stream<List<Reminder>> watchReminders({bool fired = false}) {
    final q = _db.select(_db.reminders)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.scheduledAt)]);
    if (!fired) q.where((t) => t.firedAt.isNull());
    return q.watch();
  }

  Future<Reminder?> byUuid(String uuid) => (_db.select(
    _db.reminders,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Future<String> schedule({
    required DaeItemType itemType,
    required String itemUuid,
    required String title,
    required DateTime scheduledAt,
  }) async {
    final uuid = newUuid();
    await _db
        .into(_db.reminders)
        .insert(
          RemindersCompanion.insert(
            uuid: uuid,
            itemType: itemType,
            itemUuid: itemUuid,
            title: Value(title),
            scheduledAt: scheduledAt,
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
    return uuid;
  }

  /// Marks a reminder as delivered (PATCH /api/reminders/{uuid}/fire on the
  /// server side).
  Future<void> fire(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db
        .update(_db.reminders)
        .replace(
          row.copyWith(
            firedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
  }

  Future<void> cancel(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null || row.deletedAt != null) return;
    await _db
        .update(_db.reminders)
        .replace(
          row.copyWith(
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _outbox.queueDelete(OutboxTable.reminders, uuid);
  }

  Future<void> _queue(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _outbox.queueUpsert(OutboxTable.reminders, uuid, {
      'uuid': row.uuid,
      'item_type': row.itemType.wire,
      'item_uuid': row.itemUuid,
      'title': row.title,
      'scheduled_at': row.scheduledAt.toUtc().toIso8601String(),
      if (row.firedAt != null)
        'fired_at': row.firedAt!.toUtc().toIso8601String(),
      'updated_at': row.updatedAt.toUtc().toIso8601String(),
    });
  }
}
