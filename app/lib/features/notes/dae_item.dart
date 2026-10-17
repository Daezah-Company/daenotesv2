import 'package:flutter/foundation.dart';

import '../../core/dae_types.dart';
import '../../data/db/database.dart';
import '../../data/model/enums.dart';

/// A typed reference to an item (note or todo) by its client-owned uuid.
/// Used as the family key for thread / link watches (contract §3: uuid is the
/// only stable identity, never the integer id).
@immutable
class DaeItemRef {
  const DaeItemRef(this.type, this.uuid);

  final DaeItemType type;
  final String uuid;

  @override
  bool operator ==(Object other) =>
      other is DaeItemRef && other.type == type && other.uuid == uuid;

  @override
  int get hashCode => Object.hash(type, uuid);
}

/// Unified read-only view of a note or todo, so the inbox and the link picker
/// can render both kinds from one list without a Material chip to tell them
/// apart — the [DaeItemType] drives the type mark and the thread rail.
@immutable
class DaeItem {
  const DaeItem({
    required this.type,
    required this.uuid,
    required this.title,
    required this.preview,
    required this.updatedAt,
    this.done = false,
    this.pinned = false,
    this.priority,
    this.dueAt,
    this.remindAt,
  });

  factory DaeItem.fromNote(Note n) => DaeItem(
    type: DaeItemType.note,
    uuid: n.uuid,
    title: n.title,
    preview: n.body,
    updatedAt: n.updatedAt,
    pinned: n.pinned,
  );

  factory DaeItem.fromTodo(Todo t) => DaeItem(
    type: DaeItemType.todo,
    uuid: t.uuid,
    title: t.title,
    preview: t.notes ?? '',
    updatedAt: t.updatedAt,
    done: t.done,
    priority: t.priority,
    dueAt: t.dueAt,
    remindAt: t.remindAt,
  );

  final DaeItemType type;
  final String uuid;
  final String title;
  final String preview;
  final DateTime updatedAt;
  final bool done;
  final bool pinned;
  final TodoPriority? priority;
  final DateTime? dueAt;
  final DateTime? remindAt;

  DaeItemRef get ref => DaeItemRef(type, uuid);

  /// A single-line excerpt of the body / note, for the row subtitle.
  String get excerpt => preview.trim().split('\n').first;

  /// Title falls back to the excerpt or an invitation when untitled.
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final e = excerpt;
    return e.isEmpty ? 'Tanpa judul' : e;
  }
}

/// The other endpoint of a link, given the item we are looking from.
DaeItemRef daeOtherEndpoint(DaeItemType fromType, String fromUuid, Link link) {
  final isSource = link.sourceType == fromType && link.sourceUuid == fromUuid;
  return isSource
      ? DaeItemRef(link.targetType, link.targetUuid)
      : DaeItemRef(link.sourceType, link.sourceUuid);
}
