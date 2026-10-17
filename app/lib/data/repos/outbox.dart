import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// The tables the outbox knows about — matches the sync push/pull groups.
enum OutboxTable {
  notes('notes'),
  todos('todos'),
  links('links'),
  reminders('reminders');

  const OutboxTable(this.wire);
  final String wire;
}

/// Local-first write intent store. Repositories queue here; SyncEngine
/// drains it. Nothing in the UI path ever waits for the network.
class Outbox {
  Outbox(this._db);

  final AppDatabase _db;

  Future<void> queueUpsert(
    OutboxTable table,
    String uuid,
    Map<String, Object?> payload,
  ) => _db
      .into(_db.pendingChanges)
      .insertOnConflictUpdate(
        PendingChangesCompanion.insert(
          changeTable: table.wire,
          uuid: uuid,
          operation: 'upsert',
          payload: jsonEncode(payload),
          queuedAt: DateTime.now(),
        ),
      );

  Future<void> queueDelete(OutboxTable table, String uuid) => _db
      .into(_db.pendingChanges)
      .insertOnConflictUpdate(
        PendingChangesCompanion.insert(
          changeTable: table.wire,
          uuid: uuid,
          operation: 'delete',
          payload: '{}',
          queuedAt: DateTime.now(),
        ),
      );

  Future<void> remove(OutboxTable table, String uuid) => (_db.delete(
    _db.pendingChanges,
  )..where((t) => t.changeTable.equals(table.wire) & t.uuid.equals(uuid))).go();

  Future<void> clear() => _db.delete(_db.pendingChanges).go();

  Future<List<PendingChange>> all() => _db.select(_db.pendingChanges).get();

  Stream<int> watchPendingCount() => _db.pendingChanges.count().watchSingle();

  Future<void> markAttempt(OutboxTable table, String uuid, String error) async {
    final row =
        await (_db.select(_db.pendingChanges)..where(
              (t) => t.changeTable.equals(table.wire) & t.uuid.equals(uuid),
            ))
            .getSingleOrNull();
    if (row == null) return;
    await _db
        .update(_db.pendingChanges)
        .replace(
          row.copyWith(attempts: row.attempts + 1, lastError: Value(error)),
        );
  }

  Map<String, Object?> decodePayload(PendingChange row) =>
      (jsonDecode(row.payload) as Map).cast<String, Object?>();
}
