import 'package:drift/drift.dart';

import '../db/database.dart';
import '../model/uuid.dart';
import 'outbox.dart';

/// Local-first notes store. Reads come straight from drift (the UI never
/// blocks on the network); writes stamp `updated_at` and queue the outbox.
class NotesRepository {
  NotesRepository(this._db, this._outbox);

  final AppDatabase _db;
  final Outbox _outbox;

  // ------------------------------------------------------------- watches

  /// Active (not deleted) notes, optionally including archived.
  Stream<List<Note>> watchNotes({
    String? query,
    bool archived = false,
    bool archivedOnly = false,
  }) {
    final q = _db.select(_db.notes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    if (archivedOnly) {
      q.where((t) => t.archivedAt.isNotNull());
    } else if (!archived) {
      q.where((t) => t.archivedAt.isNull());
    }
    final needle = query?.trim();
    if (needle != null && needle.isNotEmpty) {
      final like = '%$needle%';
      q.where((t) => t.title.like(like) | t.body.like(like));
    }
    return q.watch();
  }

  Stream<Note?> watchNote(String uuid) => (_db.select(
    _db.notes,
  )..where((t) => t.uuid.equals(uuid))).watchSingleOrNull();

  Future<Note?> byUuid(String uuid) => (_db.select(
    _db.notes,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  // ------------------------------------------------------------- writes

  Future<String> create({
    String title = '',
    String body = '',
    String? color,
    String? groupName,
    bool pinned = false,
  }) async {
    final uuid = newUuid();
    final now = DateTime.now();
    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            uuid: uuid,
            title: Value(title),
            body: Value(body),
            color: Value(color),
            groupName: Value(groupName),
            pinned: Value(pinned),
            updatedAt: now,
          ),
        );
    await _queue(uuid);
    return uuid;
  }

  Future<void> update(
    String uuid, {
    String? title,
    String? body,
    String? color,
    String? groupName,
    bool? pinned,
  }) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db
        .update(_db.notes)
        .replace(
          row.copyWith(
            title: title ?? row.title,
            body: body ?? row.body,
            color: Value(color ?? row.color),
            groupName: Value(groupName ?? row.groupName),
            pinned: pinned ?? row.pinned,
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
  }

  Future<void> setPinned(String uuid, bool pinned) =>
      update(uuid, pinned: pinned);

  Future<void> archive(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db
        .update(_db.notes)
        .replace(
          row.copyWith(
            archivedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
  }

  Future<void> restore(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db.update(_db.notes).replace(_clearArchive(row));
    await _queue(uuid);
  }

  /// Idempotent soft delete — the tombstone syncs to the server.
  Future<void> delete(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null || row.deletedAt != null) return;
    await _db
        .update(_db.notes)
        .replace(
          row.copyWith(
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _outbox.queueDelete(OutboxTable.notes, uuid);
  }

  Note _clearArchive(Note row) => row.copyWith(
    archivedAt: Value<DateTime?>(null),
    updatedAt: DateTime.now(),
  );

  Future<void> _queue(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _outbox.queueUpsert(OutboxTable.notes, uuid, toPayload(row));
  }

  /// API field names (contract §4: {uuid,title,body,color,pinned});
  /// `updated_at` rides along for last-write-wins on the server.
  static Map<String, Object?> toPayload(Note row) => {
    'uuid': row.uuid,
    'title': row.title,
    'body': row.body,
    'color': row.color,
    'group_name': row.groupName,
    'pinned': row.pinned,
    'archived_at': row.archivedAt?.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}
