import 'dart:convert';

import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/api/api_client.dart';
import 'package:daenotes/data/api/token_storage.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/model/enums.dart';
import 'package:daenotes/data/repos/links_repository.dart';
import 'package:daenotes/data/repos/notes_repository.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/reminders_repository.dart';
import 'package:daenotes/data/repos/todos_repository.dart';
import 'package:daenotes/data/sync/network_status.dart';
import 'package:daenotes/data/sync/sync_engine.dart';
import 'package:daenotes/data/sync/transport.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keys that belong to the dead "server integer id" model. docs/CONTRACT.md
/// §3 is explicit: identity and every cross-item reference are the client's
/// `uuid`, and the server bigint primary key never reaches the API surface —
/// so none of these may ever appear in a push body.
const _forbiddenKeys = {'id', 'server_id', 'source_id', 'target_id', 'item_id'};

/// Walks a decoded wire body and fails on any forbidden key.
void expectNoServerIdKeys(Object? node, {String path = 'body'}) {
  if (node is Map) {
    for (final entry in node.entries) {
      final key = '${entry.key}';
      expect(
        _forbiddenKeys.contains(key),
        isFalse,
        reason: '$path.$key is a server integer id; the wire is uuid-keyed',
      );
      expectNoServerIdKeys(entry.value, path: '$path.$key');
    }
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      expectNoServerIdKeys(node[i], path: '$path[$i]');
    }
  }
}

/// Records the exact JSON body handed to POST /api/sync/push (the cycle also
/// issues GET /api/sync/changes, so only the push call is captured).
class _PushBodyCapturingAdapter implements HttpClientAdapter {
  _PushBodyCapturingAdapter(this.responseData);

  final Map<String, Object?> responseData;
  String? pushPath;
  Object? sentBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/sync/push')) {
      pushPath = options.path;
      sentBody = options.data;
    }
    return ResponseBody.fromString(
      jsonEncode({'data': responseData}),
      200,
      headers: const {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StubTokens extends TokenStorage {
  @override
  Future<String?> readToken() async => 'test-token';
}

/// Minimal [SyncTransport] fake — the engine needs no running backend.
class _RecordingTransport implements SyncTransport {
  final List<SyncPushPayload> pushes = [];
  SyncPullResult pullResult = SyncPullResult(
    notes: const [],
    todos: const [],
    links: const [],
    reminders: const [],
    deleted: const {},
    serverTime: DateTime.utc(2026, 1, 1),
  );

  SyncPushResult Function(SyncPushPayload payload)? pushHandler;

  @override
  Future<SyncPushResult> push(SyncPushPayload payload) async {
    pushes.add(payload);
    if (pushHandler != null) return pushHandler!(payload);
    return SyncPushResult(
      accepted: [
        for (final r in payload.notes)
          SyncAccepted(table: 'notes', uuid: '${r['uuid']}'),
        for (final r in payload.todos)
          SyncAccepted(table: 'todos', uuid: '${r['uuid']}'),
        for (final r in payload.links)
          SyncAccepted(table: 'links', uuid: '${r['uuid']}'),
        for (final r in payload.reminders)
          SyncAccepted(table: 'reminders', uuid: '${r['uuid']}'),
        for (final d in payload.deletes)
          SyncAccepted(table: d.type, uuid: d.uuid),
      ],
      conflicts: const [],
      serverTime: DateTime.utc(2026, 1, 2),
    );
  }

  @override
  Future<SyncPullResult> pull(DateTime? since) async => pullResult;
}

void main() {
  late AppDatabase db;
  late Outbox outbox;
  late NotesRepository notes;
  late TodosRepository todos;
  late LinksRepository links;
  late RemindersRepository reminders;
  late _RecordingTransport transport;
  late NetworkStatus network;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    notes = NotesRepository(db, outbox);
    todos = TodosRepository(db, outbox);
    links = LinksRepository(db, outbox);
    reminders = RemindersRepository(db, outbox);
    transport = _RecordingTransport();
    network = NetworkStatus();
    engine = SyncEngine(
      db: db,
      transport: transport,
      outbox: outbox,
      network: network,
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  Future<Link?> storedLink(String uuid) => (db.select(
    db.links,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Future<Reminder?> storedReminder(String uuid) => (db.select(
    db.reminders,
  )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  group('push body is uuid-keyed end to end (contract §3/§4)', () {
    test('link row carries source_uuid/target_uuid and nothing else', () async {
      final noteUuid = await notes.create(title: 'a');
      final todoUuid = await todos.create(title: 'b');
      final linkUuid = await links.link(
        sourceType: DaeItemType.note,
        sourceUuid: noteUuid,
        targetType: DaeItemType.todo,
        targetUuid: todoUuid,
        label: 'rel',
      );

      final row = (await engine.buildPushPayload()).links.single;

      expect(row.keys.toSet(), {
        'uuid',
        'source_type',
        'source_uuid',
        'target_type',
        'target_uuid',
        'label',
        'updated_at',
      });
      expect(row['uuid'], linkUuid);
      expect(row['source_uuid'], noteUuid);
      expect(row['target_uuid'], todoUuid);
      expect(row.containsKey('source_id'), isFalse);
      expect(row.containsKey('target_id'), isFalse);
    });

    test('reminder row carries item_uuid, never item_id', () async {
      final todoUuid = await todos.create(title: 'b');
      final reminderUuid = await reminders.schedule(
        itemType: DaeItemType.todo,
        itemUuid: todoUuid,
        title: 'ring',
        scheduledAt: DateTime.utc(2026, 6, 1, 9),
      );

      final row = (await engine.buildPushPayload()).reminders.single;

      expect(row.keys.toSet(), {
        'uuid',
        'item_type',
        'item_uuid',
        'title',
        'scheduled_at',
        'updated_at',
      });
      expect(row['uuid'], reminderUuid);
      expect(row['item_uuid'], todoUuid);
      expect(row['item_type'], 'todo');
      expect(row.containsKey('item_id'), isFalse);
    });

    test('whole POST /api/sync/push body has no integer id anywhere', () async {
      await notes.create(title: 'a');
      final note = await notes.create(title: 'b');
      await todos.create(title: 't');
      await links.link(
        sourceType: DaeItemType.note,
        sourceUuid: note,
        targetType: DaeItemType.todo,
        targetUuid: 'a-todo-that-is-not-local-yet',
      );
      await reminders.schedule(
        itemType: DaeItemType.note,
        itemUuid: note,
        title: 'ring',
        scheduledAt: DateTime.utc(2026, 6, 1, 9),
      );

      await engine.syncOnce();

      final body = transport.pushes.single.toJson();
      expectNoServerIdKeys(body);
      final wire = jsonEncode(body);
      expect(wire, isNot(contains('source_id')));
      expect(wire, isNot(contains('target_id')));
      expect(wire, isNot(contains('item_id')));
      expect(wire, isNot(contains('server_id')));
      // A link whose endpoints were never pushed still goes out immediately:
      // the server resolves uuid -> row itself (PUSH_ORDER notes->todos->links).
      expect(body['links'], hasLength(1));
      expect(body['reminders'], hasLength(1));
      expect(body['deletes'], isEmpty);
    });

    test(
      'a stale queue row with integer ids cannot put them back on the wire',
      () async {
        // Simulates pending changes written by the old (id-translating) build.
        await outbox.queueUpsert(OutboxTable.links, 'legacy-link', {
          'uuid': 'legacy-link',
          'id': 99,
          'server_id': 99,
          'source_type': 'note',
          'source_uuid': 'note-a',
          'source_id': 7,
          'target_type': 'todo',
          'target_uuid': 'todo-b',
          'target_id': 8,
          'label': null,
          'updated_at': DateTime.utc(2026, 5, 5).toIso8601String(),
        });
        await outbox.queueUpsert(OutboxTable.reminders, 'legacy-reminder', {
          'uuid': 'legacy-reminder',
          'id': 55,
          'server_id': 55,
          'item_type': 'note',
          'item_uuid': 'note-a',
          'item_id': 7,
          'title': 'ping',
          'scheduled_at': DateTime.utc(2026, 5, 5).toIso8601String(),
          'updated_at': DateTime.utc(2026, 5, 5).toIso8601String(),
        });

        final body = (await engine.buildPushPayload()).toJson();
        expectNoServerIdKeys(body);
        expect(
          (body['links']! as List).cast<Map<String, Object?>>().single,
          isNot(contains('source_id')),
        );
        expect(
          (body['links']! as List)
              .cast<Map<String, Object?>>()
              .single['source_uuid'],
          'note-a',
        );
        expect(
          (body['reminders']! as List)
              .cast<Map<String, Object?>>()
              .single['item_uuid'],
          'note-a',
        );
      },
    );

    test('payload normalizers drop everything but the uuid contract', () async {
      expect(SyncEngine.linkPushPayload({'uuid': 'l', 'source_id': 3}), isNull);
      expect(
        SyncEngine.linkPushPayload({
          'uuid': 'l',
          'source_uuid': 'a',
          'target_uuid': 'b',
          'item_id': 3,
          'id': 9,
        })!.keys.toSet(),
        {
          'uuid',
          'source_type',
          'source_uuid',
          'target_type',
          'target_uuid',
          'label',
          'updated_at',
        },
      );
      expect(
        SyncEngine.reminderPushPayload({'uuid': 'r', 'item_id': 3}),
        isNull,
      );
      expect(
        SyncEngine.reminderPushPayload({
          'uuid': 'r',
          'item_uuid': 'a',
          'item_id': 3,
          'fired_at': null,
        })!.keys.toSet(),
        {
          'uuid',
          'item_type',
          'item_uuid',
          'title',
          'scheduled_at',
          'updated_at',
        },
      );
      expect(
        SyncEngine.reminderPushPayload({
          'uuid': 'r',
          'item_uuid': 'a',
          'fired_at': '2026-06-01T09:00:00Z',
        })!.keys.toSet(),
        contains('fired_at'),
      );
    });

    test(
      'accepted echo of {type, uuid} drains the outbox; syncedAt marks it',
      () async {
        final noteUuid = await notes.create(title: 'a');
        final todoUuid = await todos.create(title: 'b');
        await links.link(
          sourceType: DaeItemType.note,
          sourceUuid: noteUuid,
          targetType: DaeItemType.todo,
          targetUuid: todoUuid,
        );

        // The backend labels accepted rows by item kind, singular.
        transport.pushHandler = (payload) => SyncPushResult(
          accepted: [
            for (final r in payload.notes)
              SyncAccepted(table: 'note', uuid: '${r['uuid']}'),
            for (final r in payload.todos)
              SyncAccepted(table: 'todo', uuid: '${r['uuid']}'),
            for (final r in payload.links)
              SyncAccepted(table: 'link', uuid: '${r['uuid']}'),
          ],
          conflicts: const [],
        );

        await engine.syncOnce();

        expect(await outbox.all(), isEmpty);
        expect((await notes.byUuid(noteUuid))?.syncedAt, isNotNull);
        expect((await todos.byUuid(todoUuid))?.syncedAt, isNotNull);
        expect(await db.select(db.links).get(), hasLength(1));
      },
    );

    test(
      'read-only rejection restores the server row and clears local write',
      () async {
        final uuid = await notes.create(title: 'local unauthorized edit');
        transport.pushHandler = (_) => SyncPushResult(
          accepted: const [],
          conflicts: const [],
          readOnly: [
            SyncConflict(
              table: 'note',
              uuid: uuid,
              serverRow: {
                'uuid': uuid,
                'owner_user_id': 41,
                'title': 'owner canonical value',
                'body': 'owner body',
                'updated_at': '2026-06-01T09:00:00Z',
              },
            ),
          ],
        );

        await engine.syncOnce();

        expect(await outbox.all(), isEmpty);
        final row = await notes.byUuid(uuid);
        expect(row?.title, 'owner canonical value');
        expect(row?.ownerUserId, 41);
        expect(row?.deletedAt, isNull);
      },
    );
  });

  group('ApiSyncTransport against the real response shape', () {
    test('POSTs uuid references to /api/sync/push', () async {
      final noteUuid = await notes.create(title: 'a');
      final todoUuid = await todos.create(title: 'b');
      final linkUuid = await links.link(
        sourceType: DaeItemType.note,
        sourceUuid: noteUuid,
        targetType: DaeItemType.todo,
        targetUuid: todoUuid,
      );
      final reminderUuid = await reminders.schedule(
        itemType: DaeItemType.note,
        itemUuid: noteUuid,
        title: 'ring',
        scheduledAt: DateTime.utc(2026, 6, 1, 9),
      );

      final adapter = _PushBodyCapturingAdapter({
        // Straight from SyncController::push: `accepted` echoes {type, uuid}
        // only — there is no id to learn from.
        'accepted': [
          {'type': 'note', 'uuid': noteUuid},
          {'type': 'todo', 'uuid': todoUuid},
          {'type': 'link', 'uuid': linkUuid},
          {'type': 'reminder', 'uuid': reminderUuid},
        ],
        'conflicts': <Object?>[],
        'server_time': '2026-01-02T03:04:05Z',
      });
      final api = ApiClient(
        tokens: _StubTokens(),
        dio: Dio(BaseOptions(baseUrl: 'http://localhost/api'))
          ..httpClientAdapter = adapter,
      );

      final live = SyncEngine(
        db: db,
        transport: ApiSyncTransport(api),
        outbox: outbox,
        network: network,
      );
      addTearDown(live.dispose);
      await live.syncOnce();

      expect(adapter.pushPath, '/sync/push');
      final sent = adapter.sentBody;
      final decoded = jsonDecode(sent is String ? sent : jsonEncode(sent));
      expectNoServerIdKeys(decoded);

      final pushed = decoded! as Map<String, Object?>;
      final link = (pushed['links']! as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(link['source_uuid'], noteUuid);
      expect(link['target_uuid'], todoUuid);
      final reminder = (pushed['reminders']! as List)
          .cast<Map<String, Object?>>()
          .single;
      expect(reminder['item_uuid'], noteUuid);

      expect(await outbox.all(), isEmpty);
      expect((await notes.byUuid(noteUuid))?.syncedAt, isNotNull);
    });

    test('an id in the accepted echo is ignored, not stored', () async {
      final adapter = _PushBodyCapturingAdapter({
        'accepted': [
          {'type': 'note', 'uuid': 'n-1', 'id': 1234},
        ],
        'conflicts': <Object?>[],
        'server_time': '2026-01-02T03:04:05Z',
      });
      final api = ApiClient(
        tokens: _StubTokens(),
        dio: Dio(BaseOptions(baseUrl: 'http://localhost/api'))
          ..httpClientAdapter = adapter,
      );

      final result = await ApiSyncTransport(api).push(
        const SyncPushPayload(
          notes: [
            {'uuid': 'n-1', 'title': 'x', 'updated_at': '2026-01-01T00:00:00Z'},
          ],
        ),
      );

      expect(result.accepted.single.table, 'note');
      expect(result.accepted.single.uuid, 'n-1');
      expect(result.conflicts, isEmpty);
      expect(result.serverTime, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });
  });

  group('pull applies uuid references', () {
    test('link and reminder rows land without endpoint resolution', () async {
      transport.pullResult = SyncPullResult(
        notes: const [],
        todos: const [],
        links: [
          {
            'uuid': 'link-remote',
            'source_type': 'note',
            'source_uuid': 'remote-note',
            'target_type': 'todo',
            'target_uuid': 'remote-todo',
            'label': 'thread',
            'updated_at': '2026-05-05T00:00:00Z',
          },
        ],
        reminders: [
          {
            'uuid': 'remind-remote',
            'item_type': 'todo',
            'item_uuid': 'remote-todo',
            'title': 'ring',
            'scheduled_at': '2026-06-01T09:00:00Z',
            'updated_at': '2026-05-05T00:00:00Z',
          },
        ],
        deleted: const {},
        serverTime: DateTime.utc(2026, 5, 6),
      );

      await engine.syncOnce();

      final link = await storedLink('link-remote');
      expect(link, isNotNull);
      expect(link!.sourceUuid, 'remote-note');
      expect(link.targetUuid, 'remote-todo');
      expect(link.sourceType, DaeItemType.note);
      expect(link.targetType, DaeItemType.todo);

      final reminder = await storedReminder('remind-remote');
      expect(reminder, isNotNull);
      expect(reminder!.itemUuid, 'remote-todo');
      expect(reminder.itemType, DaeItemType.todo);
    });

    test('a row that only carries integer ids is not stored', () async {
      transport.pullResult = SyncPullResult(
        notes: const [],
        todos: const [],
        links: [
          {
            'uuid': 'legacy-1',
            'source_type': 'note',
            'source_id': 4,
            'target_type': 'todo',
            'target_id': 5,
            'updated_at': '2026-05-05T00:00:00Z',
          },
        ],
        reminders: [
          {
            'uuid': 'legacy-2',
            'item_type': 'note',
            'item_id': 4,
            'updated_at': '2026-05-05T00:00:00Z',
          },
        ],
        deleted: const {},
        serverTime: DateTime.utc(2026, 5, 6),
      );

      await engine.syncOnce();

      expect(await storedLink('legacy-1'), isNull);
      expect(await storedReminder('legacy-2'), isNull);
    });

    test(
      'note/todo rows keep only uuid + fields; stray id is discarded',
      () async {
        transport.pullResult = SyncPullResult(
          notes: [
            {
              'id': 77,
              'uuid': 'remote-note',
              'title': 'from server',
              'body': 'b',
              'color': null,
              'pinned': true,
              'updated_at': '2026-05-05T00:00:00Z',
            },
          ],
          todos: [
            {
              'id': 88,
              'uuid': 'remote-todo',
              'title': 'todo from server',
              'notes': 'detail',
              'done': false,
              'priority': 'high',
              'updated_at': '2026-05-05T00:00:00Z',
            },
          ],
          links: const [],
          reminders: const [],
          deleted: const {},
          serverTime: DateTime.utc(2026, 5, 6),
        );

        await engine.syncOnce();

        final note = await notes.byUuid('remote-note');
        expect(note?.title, 'from server');
        expect(note?.pinned, isTrue);
        final todo = await todos.byUuid('remote-todo');
        expect(todo?.notes, 'detail');
        expect(todo?.priority, TodoPriority.high);
        // Nothing on the local row can hold a server id any more: the only
        // "synced" marker is synced_at.
        expect(note?.syncedAt, isNotNull);
      },
    );
  });
}
