import 'package:drift/drift.dart';

import '../db/database.dart';
import '../model/enums.dart';
import '../model/uuid.dart';
import 'outbox.dart';

/// Local-first todos store — same outbox pattern as [NotesRepository].
class TodosRepository {
  TodosRepository(this._db, this._outbox);

  final AppDatabase _db;
  final Outbox _outbox;

  // ------------------------------------------------------------- watches

  /// Active todos; `done == null` means "both".
  Stream<List<Todo>> watchTodos({
    String? query,
    bool? done,
    DateTime? dueBefore,
    bool archived = false,
    bool archivedOnly = false,
  }) {
    final q = _db.select(_db.todos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.done),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    if (archivedOnly) {
      q.where((t) => t.archivedAt.isNotNull());
    } else if (!archived) {
      q.where((t) => t.archivedAt.isNull());
    }
    if (done != null) q.where((t) => t.done.equals(done));
    if (dueBefore != null) {
      q.where(
        (t) =>
            t.dueAt.isBiggerOrEqualValue(DateTime(1970)) &
            t.dueAt.isSmallerOrEqualValue(dueBefore),
      );
    }
    final needle = query?.trim();
    if (needle != null && needle.isNotEmpty) {
      q.where((t) => t.title.like('%$needle%'));
    }
    return q.watch();
  }

  Stream<Todo?> watchTodo(String uuid) => (_db.select(
    _db.todos,
  )..where((t) => t.uuid.equals(uuid))).watchSingleOrNull();

  Future<Todo?> byUuid(String uuid) => (_db.select(
    _db.todos,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  // ------------------------------------------------------------- writes

  Future<String> create({
    required String title,
    String? notes,
    String? groupName,
    TodoPriority priority = TodoPriority.normal,
    DateTime? dueAt,
    DateTime? remindAt,
  }) async {
    final uuid = newUuid();
    final now = DateTime.now();
    await _db
        .into(_db.todos)
        .insert(
          TodosCompanion.insert(
            uuid: uuid,
            title: Value(title),
            notes: Value(notes),
            groupName: Value(groupName),
            priority: Value(priority),
            dueAt: Value(dueAt),
            remindAt: Value(remindAt),
            updatedAt: now,
          ),
        );
    await _queue(uuid);
    return uuid;
  }

  /// A missing argument leaves the field untouched; `Value(null)` clears it.
  /// `Value` is the only way to tell those two apart for a nullable column.
  Future<void> update(
    String uuid, {
    String? title,
    Value<String?>? notes,
    String? groupName,
    TodoPriority? priority,
    Value<DateTime?>? dueAt,
    Value<DateTime?>? remindAt,
  }) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db
        .update(_db.todos)
        .replace(
          row.copyWith(
            title: title ?? row.title,
            notes: notes ?? Value(row.notes),
            groupName: Value(groupName ?? row.groupName),
            priority: priority ?? row.priority,
            dueAt: dueAt ?? Value(row.dueAt),
            remindAt: remindAt ?? Value(row.remindAt),
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
  }

  /// Completes/un-completes; mirrors PATCH /api/todos/{uuid}/toggle.
  Future<void> toggle(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    final now = DateTime.now();
    await _db
        .update(_db.todos)
        .replace(
          row.copyWith(
            done: !row.done,
            doneAt: row.done ? Value<DateTime?>(null) : Value(now),
            updatedAt: now,
          ),
        );
    await _queue(uuid);
  }

  Future<void> archive(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _db
        .update(_db.todos)
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
    await _db
        .update(_db.todos)
        .replace(
          row.copyWith(
            archivedAt: const Value<DateTime?>(null),
            updatedAt: DateTime.now(),
          ),
        );
    await _queue(uuid);
  }

  Future<void> delete(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null || row.deletedAt != null) return;
    await _db
        .update(_db.todos)
        .replace(
          row.copyWith(
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _outbox.queueDelete(OutboxTable.todos, uuid);
  }

  Future<void> _queue(String uuid) async {
    final row = await byUuid(uuid);
    if (row == null) return;
    await _outbox.queueUpsert(OutboxTable.todos, uuid, toPayload(row));
  }

  /// API field names (contract §4: {uuid,title,notes,priority,due_at,remind_at}).
  static Map<String, Object?> toPayload(Todo row) => {
    'uuid': row.uuid,
    'title': row.title,
    'notes': row.notes,
    'group_name': row.groupName,
    'done': row.done,
    if (row.doneAt != null) 'done_at': row.doneAt!.toUtc().toIso8601String(),
    'priority': row.priority.wire,
    if (row.dueAt != null) 'due_at': row.dueAt!.toUtc().toIso8601String(),
    if (row.remindAt != null)
      'remind_at': row.remindAt!.toUtc().toIso8601String(),
    'archived_at': row.archivedAt?.toUtc().toIso8601String(),
    'updated_at': row.updatedAt.toUtc().toIso8601String(),
  };
}
