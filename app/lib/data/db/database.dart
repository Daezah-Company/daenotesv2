import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/dae_types.dart';
import '../model/enums.dart';

part 'database.g.dart';

/// Local mirror of the server `notes` table (contract §3). Identity is the
/// client-owned `uuid` — the server's bigint `id` never appears on the API
/// surface, so it is not mirrored here. "Synced" is tracked by [syncedAt].
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
}

class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
  TextColumn get priority => text()
      .map(const TodoPriorityConverter())
      .withDefault(const Constant('normal'))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get remindAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Links are stored and pushed by endpoint *uuids* — exactly the wire shape
/// of contract §4 (`{uuid,source_type,source_uuid,target_type,target_uuid,
/// label,updated_at}`). Endpoint rows can legitimately be missing locally
/// when a link arrives before its note/todo; they land on a later pull.
class Links extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get sourceType => text().map(const DaeItemTypeConverter())();
  TextColumn get sourceUuid => text()();
  TextColumn get targetType => text().map(const DaeItemTypeConverter())();
  TextColumn get targetUuid => text()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
}

class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get itemType => text().map(const DaeItemTypeConverter())();
  TextColumn get itemUuid => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get firedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Outbox: every local write queues its intent here; SyncEngine drains it.
/// One row per (changeTable, uuid) — later writes to the same item replace
/// the earlier payload (last-write-wins before it even leaves the device).
class PendingChanges extends Table {
  TextColumn get changeTable => text()(); // notes|todos|links|reminders
  TextColumn get uuid => text()();
  TextColumn get operation => text()(); // upsert|delete
  TextColumn get payload => text()(); // JSON object, API field names
  DateTimeColumn get queuedAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// One pending row per item: a newer local write replaces the older
  /// queued payload instead of stacking behind it.
  @override
  Set<Column> get primaryKey => {changeTable, uuid};
}

/// Key/value store for sync bookkeeping (`lastSyncedAt`, device id…).
class Metas extends Table {
  TextColumn get metaKey => text()();
  TextColumn get metaValue => text()();

  @override
  Set<Column> get primaryKey => {metaKey};
}

@DriftDatabase(tables: [Notes, Todos, Links, Reminders, PendingChanges, Metas])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.evaluator);

  /// Production constructor — file-backed via drift_flutter.
  AppDatabase.open() : super(driftDatabase(name: 'daenotes'));

  @override
  int get schemaVersion => 1;

  /// The server-int columns (`server_id`, `source_id`, `target_id`,
  /// `item_id`) were dropped without a version bump on purpose: every one of
  /// them was nullable and nothing read them, and drift's generated SQL names
  /// columns explicitly, so an already-installed database that still carries
  /// those dead columns keeps working — they are simply never referenced.
}

/// Meta keys used by the data layer.
abstract final class MetaKeys {
  static const lastSyncedAt = 'lastSyncedAt';
}
