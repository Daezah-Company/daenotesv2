import 'dart:ui';

import 'package:drift/drift.dart';

import '../../core/dae_types.dart';
import '../../core/ds_tokens.dart';
import '../db/database.dart';
import '../model/uuid.dart';
import 'outbox.dart';

/// Connections between items. Locally keyed by endpoint uuids; the payload
/// builder resolves uuid -> server id at push time (see DECISIONS.md).
class LinksRepository {
  LinksRepository(this._db, this._outbox);

  final AppDatabase _db;
  final Outbox _outbox;

  // ------------------------------------------------------------- watches

  /// All live links touching an item (either direction), 1 hop.
  Stream<List<Link>> watchLinksFor(DaeItemType type, String uuid) =>
      _oneHop(type, uuid).watch();

  /// Every live link in the vault — the graph model reads through the
  /// repository like every other feature instead of touching the table.
  Stream<List<Link>> watchAllLinks() =>
      (_db.select(_db.links)..where((t) => t.deletedAt.isNull())).watch();

  /// One-shot read of the same 1-hop set. Deliberately not built on
  /// [watchLinksFor]: a single read must not create a cached drift stream,
  /// whose garbage collector only runs on a timer.
  Future<List<Link>> neighbors(DaeItemType type, String uuid) =>
      _oneHop(type, uuid).get();

  SimpleSelectStatement<$LinksTable, Link> _oneHop(
    DaeItemType type,
    String uuid,
  ) => (_db.select(_db.links)
    ..where((t) => t.deletedAt.isNull())
    ..where(
      (t) =>
          (t.sourceType.equals(type.wire) & t.sourceUuid.equals(uuid)) |
          (t.targetType.equals(type.wire) & t.targetUuid.equals(uuid)),
    ));

  /// The thread colour for an item's spine rail: colour of its first live
  /// connection, or null when the item is isolated (rail stays empty).
  Stream<Color?> watchThreadFor(DaeItemType type, String uuid) =>
      watchLinksFor(type, uuid).map((links) {
        if (links.isEmpty) return null;
        final first = links.first;
        return Ds.threadColor(first.sourceType, first.targetType);
      });

  // ------------------------------------------------------------- writes

  Future<String> link({
    required DaeItemType sourceType,
    required String sourceUuid,
    required DaeItemType targetType,
    required String targetUuid,
    String? label,
  }) async {
    final existing =
        await (_db.select(_db.links)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  ((t.sourceType.equals(sourceType.wire) &
                          t.sourceUuid.equals(sourceUuid) &
                          t.targetType.equals(targetType.wire) &
                          t.targetUuid.equals(targetUuid)) |
                      (t.sourceType.equals(targetType.wire) &
                          t.sourceUuid.equals(targetUuid) &
                          t.targetType.equals(sourceType.wire) &
                          t.targetUuid.equals(sourceUuid))),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.uuid;

    final uuid = newUuid();
    final now = DateTime.now();
    await _db
        .into(_db.links)
        .insert(
          LinksCompanion.insert(
            uuid: uuid,
            sourceType: sourceType,
            sourceUuid: sourceUuid,
            targetType: targetType,
            targetUuid: targetUuid,
            label: Value(label),
            updatedAt: now,
          ),
        );
    await _queue(uuid);
    return uuid;
  }

  Future<void> unlink(String uuid) async {
    final row = await (_db.select(
      _db.links,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (row == null || row.deletedAt != null) return;
    await _db
        .update(_db.links)
        .replace(
          row.copyWith(
            deletedAt: Value(DateTime.now()),
            updatedAt: DateTime.now(),
          ),
        );
    await _outbox.queueDelete(OutboxTable.links, uuid);
  }

  Future<void> _queue(String uuid) async {
    final row = await (_db.select(
      _db.links,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    if (row == null) return;
    await _outbox.queueUpsert(OutboxTable.links, uuid, {
      'uuid': row.uuid,
      'source_type': row.sourceType.wire,
      'source_uuid': row.sourceUuid,
      'target_type': row.targetType.wire,
      'target_uuid': row.targetUuid,
      'label': row.label,
      'updated_at': row.updatedAt.toUtc().toIso8601String(),
    });
  }
}
