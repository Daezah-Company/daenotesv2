import 'package:drift/drift.dart';

import '../../core/dae_types.dart';
import '../db/database.dart';
import '../model/enums.dart';
import 'transport.dart';

/// Writes server rows into the local drift store with last-write-wins on
/// `updated_at` (contract §4 sync semantics). Local unsynced edits that are
/// newer than the server copy are preserved.
class ServerApplier {
  ServerApplier(this._db);

  final AppDatabase _db;

  Future<void> applyAll(SyncPullResult pull) => _db.transaction(() async {
    for (final row in pull.notes) {
      await applyNote(row);
    }
    for (final row in pull.todos) {
      await applyTodo(row);
    }
    for (final row in pull.links) {
      await applyLink(row);
    }
    for (final row in pull.reminders) {
      await applyReminder(row);
    }
    pull.deleted.forEach((table, uuids) {
      for (final uuid in uuids) {
        _tombstone(table, uuid);
      }
    });
  });

  // ------------------------------------------------------------------ note

  Future<void> applyNote(Map<String, dynamic> row) async {
    final uuid = row['uuid'] as String?;
    if (uuid == null) return;
    final updated =
        parseServerDate(row['updated_at']) ?? DateTime.now().toUtc();
    final local = await (_db.select(
      _db.notes,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (local != null && local.updatedAt.toUtc().isAfter(updated)) return;
    final companion = NotesCompanion.insert(
      uuid: uuid,
      title: Value('${row['title'] ?? ''}'),
      body: Value('${row['body'] ?? ''}'),
      color: Value(row['color'] as String?),
      pinned: Value(row['pinned'] == true),
      archivedAt: Value(parseServerDate(row['archived_at'])),
      deletedAt: Value(parseServerDate(row['deleted_at'])),
      syncedAt: Value(DateTime.now()),
      updatedAt: updated.toLocal(),
    );
    // Upsert keyed on uuid (the local auto-increment `id` is not the match
    // key, so insertOnConflictUpdate's default target would miss).
    if (local == null) {
      await _db.into(_db.notes).insert(companion);
    } else {
      await (_db.update(
        _db.notes,
      )..where((t) => t.uuid.equals(uuid))).write(companion);
    }
  }

  // ------------------------------------------------------------------ todo

  Future<void> applyTodo(Map<String, dynamic> row) async {
    final uuid = row['uuid'] as String?;
    if (uuid == null) return;
    final updated =
        parseServerDate(row['updated_at']) ?? DateTime.now().toUtc();
    final local = await (_db.select(
      _db.todos,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (local != null && local.updatedAt.toUtc().isAfter(updated)) return;
    final companion = TodosCompanion.insert(
      uuid: uuid,
      title: Value('${row['title'] ?? ''}'),
      notes: Value(row['notes'] as String?),
      done: Value(row['done'] == true),
      doneAt: Value(parseServerDate(row['done_at'])),
      priority: Value(TodoPriority.fromWire(row['priority'] as String?)),
      dueAt: Value(parseServerDate(row['due_at'])),
      remindAt: Value(parseServerDate(row['remind_at'])),
      archivedAt: Value(parseServerDate(row['archived_at'])),
      deletedAt: Value(parseServerDate(row['deleted_at'])),
      syncedAt: Value(DateTime.now()),
      updatedAt: updated.toLocal(),
    );
    if (local == null) {
      await _db.into(_db.todos).insert(companion);
    } else {
      await (_db.update(
        _db.todos,
      )..where((t) => t.uuid.equals(uuid))).write(companion);
    }
  }

  // ------------------------------------------------------------------ link

  /// Server links reference endpoint *uuids* (contract §3/§4), which is what
  /// the local row stores directly. Endpoints do not have to exist locally
  /// yet — a link pulled before its note/todo is kept, and the item arrives on
  /// a later pull; the read path filters by uuid anyway.
  Future<void> applyLink(Map<String, dynamic> row) async {
    final uuid = row['uuid'] as String?;
    final sourceUuid = row['source_uuid'] as String?;
    final targetUuid = row['target_uuid'] as String?;
    if (uuid == null || sourceUuid == null || targetUuid == null) {
      return; // malformed without endpoint uuids
    }

    final updated =
        parseServerDate(row['updated_at']) ?? DateTime.now().toUtc();
    final local = await (_db.select(
      _db.links,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (local != null && local.updatedAt.toUtc().isAfter(updated)) return;
    final companion = LinksCompanion.insert(
      uuid: uuid,
      sourceType:
          DaeItemType.fromWire(row['source_type'] as String?) ??
          DaeItemType.note,
      sourceUuid: sourceUuid,
      targetType:
          DaeItemType.fromWire(row['target_type'] as String?) ??
          DaeItemType.note,
      targetUuid: targetUuid,
      label: Value(row['label'] as String?),
      deletedAt: Value(parseServerDate(row['deleted_at'])),
      updatedAt: updated.toLocal(),
    );
    if (local == null) {
      await _db.into(_db.links).insert(companion);
    } else {
      await (_db.update(
        _db.links,
      )..where((t) => t.uuid.equals(uuid))).write(companion);
    }
  }

  // --------------------------------------------------------------- reminder

  /// Same uuid-first rule as [applyLink]: the server's `item_uuid` is stored
  /// as-is; the referenced item may arrive on a later pull.
  Future<void> applyReminder(Map<String, dynamic> row) async {
    final uuid = row['uuid'] as String?;
    final itemUuid = row['item_uuid'] as String?;
    if (uuid == null || itemUuid == null) return;

    final updated =
        parseServerDate(row['updated_at']) ?? DateTime.now().toUtc();
    final local = await (_db.select(
      _db.reminders,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (local != null && local.updatedAt.toUtc().isAfter(updated)) return;
    final companion = RemindersCompanion.insert(
      uuid: uuid,
      itemType:
          DaeItemType.fromWire(row['item_type'] as String?) ?? DaeItemType.note,
      itemUuid: itemUuid,
      scheduledAt:
          parseServerDate(row['scheduled_at'])?.toLocal() ?? DateTime.now(),
      title: Value('${row['title'] ?? ''}'),
      firedAt: Value(parseServerDate(row['fired_at'])),
      deletedAt: Value(parseServerDate(row['deleted_at'])),
      updatedAt: updated.toLocal(),
    );
    if (local == null) {
      await _db.into(_db.reminders).insert(companion);
    } else {
      await (_db.update(
        _db.reminders,
      )..where((t) => t.uuid.equals(uuid))).write(companion);
    }
  }

  // ---------------------------------------------------------------- shared

  /// Adopt the server's copy during conflict resolution (server wins LWW).
  Future<void> applyConflict(
    String table,
    Map<String, dynamic> serverRow,
  ) async {
    switch (table) {
      case 'notes':
        await applyNote(serverRow);
      case 'todos':
        await applyTodo(serverRow);
      case 'links':
        await applyLink(serverRow);
      case 'reminders':
        await applyReminder(serverRow);
    }
  }

  /// Marks a row as delivered to the server. The only marker is `synced_at`:
  /// identity is the client uuid, so there is no server id to backfill and
  /// nothing else to record. Links and reminders have no `synced_at` column
  /// (contract §3) — their "synced" state is the absence of an outbox row.
  Future<void> markSynced(String table, String uuid) async {
    final now = DateTime.now();
    switch (table) {
      case 'notes':
        await (_db.update(_db.notes)..where((t) => t.uuid.equals(uuid))).write(
          NotesCompanion(syncedAt: Value(now)),
        );
      case 'todos':
        await (_db.update(_db.todos)..where((t) => t.uuid.equals(uuid))).write(
          TodosCompanion(syncedAt: Value(now)),
        );
      case 'links':
      case 'reminders':
        break;
    }
  }

  Future<void> _tombstone(String table, String uuid) async {
    final now = DateTime.now();
    switch (table) {
      case 'notes':
        await (_db.update(_db.notes)
              ..where((t) => t.uuid.equals(uuid) & t.deletedAt.isNull()))
            .write(NotesCompanion(deletedAt: Value(now), syncedAt: Value(now)));
      case 'todos':
        await (_db.update(_db.todos)
              ..where((t) => t.uuid.equals(uuid) & t.deletedAt.isNull()))
            .write(TodosCompanion(deletedAt: Value(now), syncedAt: Value(now)));
      case 'links':
        await (_db.update(_db.links)
              ..where((t) => t.uuid.equals(uuid) & t.deletedAt.isNull()))
            .write(LinksCompanion(deletedAt: Value(now)));
      case 'reminders':
        await (_db.update(_db.reminders)
              ..where((t) => t.uuid.equals(uuid) & t.deletedAt.isNull()))
            .write(RemindersCompanion(deletedAt: Value(now)));
    }
  }
}
