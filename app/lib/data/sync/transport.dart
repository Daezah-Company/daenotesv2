import 'dart:convert';

import '../api/api_client.dart';

// --------------------------------------------------------------------- DTOs

/// One accepted change echoed by /api/sync/push.
///
/// The wire shape is `{type, uuid}` only (contract §4 + SyncController):
/// identity and every cross-item reference are uuid-keyed, so the server
/// never sends its bigint primary key back and this DTO has no integer id.
class SyncAccepted {
  const SyncAccepted({required this.table, required this.uuid});
  final String table; // notes|todos|links|reminders
  final String uuid;
}

/// A conflict echoed by /api/sync/push: the server's version of the row.
class SyncConflict {
  const SyncConflict({
    required this.table,
    required this.uuid,
    required this.serverRow,
  });
  final String table;
  final String uuid;
  final Map<String, dynamic> serverRow;
}

class SyncPushResult {
  const SyncPushResult({
    required this.accepted,
    required this.conflicts,
    this.revoked = const [],
    this.readOnly = const [],
    this.serverTime,
  });
  final List<SyncAccepted> accepted;
  final List<SyncConflict> conflicts;

  /// Shared rows the server no longer exposes to this account.
  final List<SyncAccepted> revoked;

  /// Deletes/resurrections rejected because the current account is not owner.
  final List<SyncConflict> readOnly;
  final DateTime? serverTime;
}

class SyncPullResult {
  const SyncPullResult({
    required this.notes,
    required this.todos,
    required this.links,
    required this.reminders,
    required this.deleted,
    required this.serverTime,
  });

  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> todos;
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> reminders;

  /// table -> deleted uuids.
  final Map<String, List<String>> deleted;
  final DateTime serverTime;
}

class SyncDelete {
  const SyncDelete({required this.type, required this.uuid});
  final String type;
  final String uuid;

  Map<String, Object?> toJson() => {'type': type, 'uuid': uuid};
}

/// The assembled POST /api/sync/push body (contract §4):
/// `{notes:[],todos:[],links:[],reminders:[],deletes:[{type,uuid}]}`.
/// Every bucket row is uuid-keyed end to end — links carry
/// `source_uuid`/`target_uuid` and reminders carry `item_uuid`; an integer
/// server id in any of those fields is rejected by the backend.
class SyncPushPayload {
  const SyncPushPayload({
    this.notes = const [],
    this.todos = const [],
    this.links = const [],
    this.reminders = const [],
    this.deletes = const [],
  });

  final List<Map<String, Object?>> notes;
  final List<Map<String, Object?>> todos;
  final List<Map<String, Object?>> links;
  final List<Map<String, Object?>> reminders;
  final List<SyncDelete> deletes;

  bool get isEmpty =>
      notes.isEmpty &&
      todos.isEmpty &&
      links.isEmpty &&
      reminders.isEmpty &&
      deletes.isEmpty;

  Map<String, Object?> toJson() => {
    'notes': notes,
    'todos': todos,
    'links': links,
    'reminders': reminders,
    'deletes': deletes.map((d) => d.toJson()).toList(),
  };
}

/// Seam between [SyncEngine] and the wire. Tests inject a fake; production
/// uses [ApiSyncTransport]. No running backend needed for engine tests.
abstract class SyncTransport {
  Future<SyncPushResult> push(SyncPushPayload payload);
  Future<SyncPullResult> pull(DateTime? since);
}

// ------------------------------------------------------------------- API

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this._api);

  final ApiClient _api;

  @override
  Future<SyncPushResult> push(SyncPushPayload payload) async {
    final data = await _api.syncPush(payload.toJson());
    return SyncPushResult(
      accepted: (data['accepted'] as List? ?? const [])
          .map(_parseAccepted)
          .whereType<SyncAccepted>()
          .toList(),
      conflicts: (data['conflicts'] as List? ?? const [])
          .map(_parseConflict)
          .whereType<SyncConflict>()
          .toList(),
      revoked: (data['revoked'] as List? ?? const [])
          .map(_parseAccepted)
          .whereType<SyncAccepted>()
          .toList(),
      readOnly: (data['read_only'] as List? ?? const [])
          .map(_parseConflict)
          .whereType<SyncConflict>()
          .toList(),
      serverTime: parseServerDate(data['server_time']),
    );
  }

  @override
  Future<SyncPullResult> pull(DateTime? since) async {
    final data = await _api.syncChanges(since);
    List<Map<String, dynamic>> rows(String key) =>
        (data[key] as List? ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
    final deletedMap = <String, List<String>>{};
    final deleted = data['deleted'];
    if (deleted is Map) {
      deleted.forEach((key, value) {
        deletedMap['$key'] = (value as List? ?? const [])
            .map((e) => '$e')
            .toList();
      });
    }
    return SyncPullResult(
      notes: rows('notes'),
      todos: rows('todos'),
      links: rows('links'),
      reminders: rows('reminders'),
      deleted: deletedMap,
      serverTime:
          parseServerDate(data['server_time']) ?? DateTime.now().toUtc(),
    );
  }

  static SyncAccepted? _parseAccepted(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final uuid = m['uuid'] as String?;
    if (uuid == null) return null;
    return SyncAccepted(table: '${m['type'] ?? m['table'] ?? ''}', uuid: uuid);
  }

  static SyncConflict? _parseConflict(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final uuid = m['uuid'] as String?;
    final server = (m['server'] as Map?)?.cast<String, dynamic>();
    if (uuid == null || server == null) return null;
    return SyncConflict(
      table: '${m['type'] ?? m['table'] ?? ''}',
      uuid: uuid,
      serverRow: server,
    );
  }
}

/// Accepts both ISO-8601 and MySQL `Y-m-d H:i:s`.
DateTime? parseServerDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  final s = raw.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toUtc();
}

String? encodeJson(Object? value) => value == null ? null : jsonEncode(value);
