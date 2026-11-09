import 'dart:async';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/meta_dao.dart';
import '../repos/outbox.dart';
import 'network_status.dart';
import 'server_applier.dart';
import 'transport.dart';

enum SyncPhase { idle, syncing, offline, error }

/// Snapshot published on [SyncEngine.status].
class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.message,
  });

  final SyncPhase phase;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? message;

  SyncState copyWith({
    SyncPhase? phase,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? message,
  }) => SyncState(
    phase: phase ?? this.phase,
    pendingCount: pendingCount ?? this.pendingCount,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    message: message,
  );
}

/// Background sync: drains the outbox via POST /api/sync/push, pulls
/// GET /api/sync/changes?since=..., resolves conflicts last-write-wins by
/// `updated_at`, and emits [SyncState] for the UI badge. Never touches the
/// read path — the UI only ever reads drift.
///
/// Fully testable through the injected [SyncTransport] and [sleep]; tests
/// need no running backend.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.transport,
    required this.outbox,
    required this.network,
    ServerApplier? applier,
    Future<void> Function(Duration)? sleep,
    Duration Function(int attempt)? backoff,
  }) : applier = applier ?? ServerApplier(db),
       sleep = sleep ?? _timerSleep,
       backoff = backoff ?? backoffDelay;

  final AppDatabase db;
  final SyncTransport transport;
  final Outbox outbox;
  final NetworkStatus network;
  final ServerApplier applier;
  final Future<void> Function(Duration) sleep;
  final Duration Function(int) backoff;

  final _statusController = StreamController<SyncState>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _ticker;
  SyncState _state = const SyncState();
  bool _running = false;
  bool _stopped = false;
  bool _cycleActive = false;

  Stream<SyncState> get status => _statusController.stream;
  SyncState get current => _state;

  static Future<void> _timerSleep(Duration d) => Future<void>.delayed(d, () {});

  /// Start background syncing: retries on connectivity changes and ticks
  /// periodically so the outbox drains without user action.
  void start() {
    if (_running) return;
    _running = true;
    _stopped = false;
    _connectivitySub = network.changes.listen((online) {
      if (online) unawaited(syncWithRetry());
    });
    // Pull even with an empty outbox: collaborators need to receive items and
    // revocations created by another account without making a local edit first.
    _ticker = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(syncWithRetry());
    });
    unawaited(syncWithRetry());
  }

  Future<void> stop() async {
    _stopped = true;
    _running = false;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
  }

  /// Run a cycle only when something is queued.
  Future<void> syncIfPending() async {
    if (_cycleActive) return;
    final pending = await db.pendingChanges.count().getSingle();
    if (pending > 0) await syncWithRetry();
  }

  /// One push+pull cycle with NetworkStatus-aware exponential retry.
  Future<void> syncWithRetry({int maxAttempts = 6}) async {
    if (_cycleActive) return;
    _cycleActive = true;
    try {
      var attempt = 0;
      while (!_stopped) {
        if (!network.isOnline) {
          _emit(SyncPhase.offline);
          return;
        }
        try {
          await syncOnce();
          return;
        } catch (error) {
          attempt++;
          _emit(SyncPhase.error, message: '$error');
          if (attempt >= maxAttempts) return;
          await sleep(backoff(attempt - 1));
        }
      }
    } finally {
      _cycleActive = false;
    }
  }

  /// Exactly one cycle, no retry, no online check guard on push. Throws on
  /// transport failure so [syncWithRetry] can back off.
  Future<void> syncOnce() async {
    _emit(SyncPhase.syncing);

    final payload = await buildPushPayload();
    if (!payload.isEmpty) {
      final result = await transport.push(payload);
      await _applyPushResult(result);
    }

    final since = await db.readLastSyncedAt();
    final pull = await transport.pull(since);
    await applier.applyAll(pull);
    await db.setLastSyncedAt(pull.serverTime);

    final pending = await db.pendingChanges.count().getSingle();
    _state = _state.copyWith(
      phase: SyncPhase.idle,
      lastSyncAt: DateTime.now(),
      pendingCount: pending,
      message: null,
    );
    if (!_statusController.isClosed) _statusController.add(_state);
  }

  // ------------------------------------------------------------ payload

  /// Group the outbox into the /api/sync/push body.
  ///
  /// Everything on the wire is uuid-keyed (contract §3/§4): links reference
  /// `source_uuid`/`target_uuid` and reminders reference `item_uuid`, so no
  /// bucket has to wait for a server-side integer id and nothing is ever
  /// deferred. The link/reminder payloads are still rebuilt field by field
  /// instead of passed through, so a stale queue row written by an older
  /// build can never smuggle a `*_id` key back onto the wire.
  Future<SyncPushPayload> buildPushPayload() async {
    final rows = await outbox.all();
    final notes = <Map<String, Object?>>[];
    final todos = <Map<String, Object?>>[];
    final links = <Map<String, Object?>>[];
    final reminders = <Map<String, Object?>>[];
    final deletes = <SyncDelete>[];

    for (final row in rows) {
      final payload = outbox.decodePayload(row);
      switch (row.changeTable) {
        case 'notes':
          if (row.operation == 'delete') {
            deletes.add(SyncDelete(type: row.changeTable, uuid: row.uuid));
          } else {
            notes.add(payload);
          }
        case 'todos':
          if (row.operation == 'delete') {
            deletes.add(SyncDelete(type: row.changeTable, uuid: row.uuid));
          } else {
            todos.add(payload);
          }
        case 'links':
          if (row.operation == 'delete') {
            deletes.add(SyncDelete(type: row.changeTable, uuid: row.uuid));
            break;
          }
          final resolved = linkPushPayload(payload);
          if (resolved != null) links.add(resolved);
        case 'reminders':
          if (row.operation == 'delete') {
            deletes.add(SyncDelete(type: row.changeTable, uuid: row.uuid));
            break;
          }
          final resolved = reminderPushPayload(payload);
          if (resolved != null) reminders.add(resolved);
      }
    }
    return SyncPushPayload(
      notes: notes,
      todos: todos,
      links: links,
      reminders: reminders,
      deletes: deletes,
    );
  }

  /// Outbox row -> `links[]` wire row (contract §4):
  /// `{uuid,source_type,source_uuid,target_type,target_uuid,label,updated_at}`.
  /// Returns null (keeping the change queued) when an endpoint reference is
  /// missing — the server can only store a link it can resolve by uuid.
  static Map<String, Object?>? linkPushPayload(Map<String, Object?> p) {
    final uuid = p['uuid'];
    final sourceUuid = p['source_uuid'];
    final targetUuid = p['target_uuid'];
    if (uuid == null || sourceUuid == null || targetUuid == null) return null;
    return {
      'uuid': uuid,
      'source_type': p['source_type'],
      'source_uuid': sourceUuid,
      'target_type': p['target_type'],
      'target_uuid': targetUuid,
      'label': p['label'],
      'updated_at': p['updated_at'],
    };
  }

  /// Outbox row -> `reminders[]` wire row (contract §4):
  /// `{uuid,item_type,item_uuid,title,scheduled_at,updated_at,fired_at?}`.
  static Map<String, Object?>? reminderPushPayload(Map<String, Object?> p) {
    final uuid = p['uuid'];
    final itemUuid = p['item_uuid'];
    if (uuid == null || itemUuid == null) return null;
    return {
      'uuid': uuid,
      'item_type': p['item_type'],
      'item_uuid': itemUuid,
      'title': p['title'],
      'scheduled_at': p['scheduled_at'],
      if (p['fired_at'] != null) 'fired_at': p['fired_at'],
      'updated_at': p['updated_at'],
    };
  }

  // ------------------------------------------------------- push results

  /// Apply /api/sync/push's `accepted` + `conflicts`.
  ///
  /// Conflict resolution is last-write-wins by `updated_at`
  /// (docs/CONTRACT.md §4): if the server copy is strictly newer, the server
  /// wins and the local pending change is dropped; otherwise the local edit
  /// stays queued and is retried next cycle.
  Future<void> _applyPushResult(SyncPushResult result) =>
      db.transaction(() async {
        for (final a in result.accepted) {
          final table = _tableForWire(a.table);
          if (table == null) continue;
          await applier.markSynced(table.wire, a.uuid);
          await outbox.remove(table, a.uuid);
        }
        for (final c in result.conflicts) {
          final table = _tableForWire(c.table);
          if (table == null) continue;
          final localUpdatedAt = await _localUpdatedAt(table.wire, c.uuid);
          final serverUpdatedAt = parseServerDate(c.serverRow['updated_at']);
          if (serverWins(server: serverUpdatedAt, local: localUpdatedAt)) {
            await applier.applyConflict(table.wire, c.serverRow);
            await outbox.remove(table, c.uuid);
          } else {
            await outbox.markAttempt(
              table,
              c.uuid,
              'conflict kept (local newer)',
            );
          }
        }
        for (final entry in result.revoked) {
          final table = _tableForWire(entry.table);
          if (table == null) continue;
          await applier.revokeShared(table.wire, entry.uuid);
        }
        for (final entry in result.readOnly) {
          final table = _tableForWire(entry.table);
          if (table == null) continue;
          await applier.applyReadOnly(table.wire, entry.serverRow);
          await outbox.remove(table, entry.uuid);
        }
      });

  Future<DateTime?> _localUpdatedAt(String table, String uuid) async {
    switch (table) {
      case 'notes':
        final row = await (db.select(
          db.notes,
        )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        return row?.updatedAt;
      case 'todos':
        final row = await (db.select(
          db.todos,
        )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        return row?.updatedAt;
      case 'links':
        final row = await (db.select(
          db.links,
        )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        return row?.updatedAt;
      case 'reminders':
        final row = await (db.select(
          db.reminders,
        )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
        return row?.updatedAt;
      default:
        return null;
    }
  }

  /// Pure LWW decision (exposed for tests): the server wins when its
  /// `updated_at` is strictly after the local one, or when local is unknown.
  static bool serverWins({
    required DateTime? server,
    required DateTime? local,
  }) {
    if (server == null) return false;
    if (local == null) return true;
    return server.isAfter(local.toUtc());
  }

  /// Maps the `type` of a push `accepted`/`conflicts` entry to an outbox
  /// table. The server labels entries by item kind (`note`, `todo`, `link`,
  /// `reminder`, see SyncController::TYPES) while the client queues by bucket
  /// name (`notes`, …), so both spellings resolve to the same table.
  OutboxTable? _tableForWire(String wire) {
    for (final t in OutboxTable.values) {
      final singular = t.wire.substring(0, t.wire.length - 1); // notes -> note
      if (wire == t.wire || wire == singular) return t;
    }
    return null;
  }

  void _emit(SyncPhase phase, {String? message}) {
    _state = _state.copyWith(phase: phase, message: message);
    if (!_statusController.isClosed) _statusController.add(_state);
  }
}
