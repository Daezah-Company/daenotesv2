import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/data/db/meta_dao.dart';
import 'package:daenotes/data/repos/links_repository.dart';
import 'package:daenotes/data/repos/notes_repository.dart';
import 'package:daenotes/data/repos/outbox.dart';
import 'package:daenotes/data/repos/reminders_repository.dart';
import 'package:daenotes/data/sync/network_status.dart';
import 'package:daenotes/data/sync/sync_engine.dart';
import 'package:daenotes/data/sync/transport.dart';
import 'package:daenotes/core/dae_types.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Transport fake — the SyncEngine is fully testable without a backend.
class FakeSyncTransport implements SyncTransport {
  final List<SyncPushPayload> pushes = [];
  final List<DateTime?> pullCursors = [];

  SyncPushResult Function(SyncPushPayload payload)? pushHandler;
  SyncPullResult Function(DateTime? since)? pullHandler;

  @override
  Future<SyncPushResult> push(SyncPushPayload payload) async {
    pushes.add(payload);
    if (pushHandler != null) return pushHandler!(payload);
    return SyncPushResult(
      accepted: [
        for (final n in payload.notes)
          SyncAccepted(table: 'notes', uuid: '${n['uuid']}'),
        for (final t in payload.todos)
          SyncAccepted(table: 'todos', uuid: '${t['uuid']}'),
        for (final l in payload.links)
          SyncAccepted(table: 'links', uuid: '${l['uuid']}'),
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
  Future<SyncPullResult> pull(DateTime? since) async {
    pullCursors.add(since);
    if (pullHandler != null) return pullHandler!(since);
    return SyncPullResult(
      notes: const [],
      todos: const [],
      links: const [],
      reminders: const [],
      deleted: const {},
      serverTime: DateTime.utc(2026, 1, 1),
    );
  }
}

void main() {
  late AppDatabase db;
  late Outbox outbox;
  late NotesRepository notes;
  late LinksRepository links;
  late NetworkStatus network;
  late FakeSyncTransport transport;
  late SyncEngine engine;
  late List<Duration> slept;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = Outbox(db);
    notes = NotesRepository(db, outbox);
    links = LinksRepository(db, outbox);
    network = NetworkStatus();
    transport = FakeSyncTransport();
    slept = [];
    engine = SyncEngine(
      db: db,
      transport: transport,
      outbox: outbox,
      network: network,
      sleep: (d) async => slept.add(d),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  group('outbox draining', () {
    test('local note write queues and one cycle drains it', () async {
      final uuid = await notes.create(title: 'Hello thread');
      expect(await outbox.all(), hasLength(1));

      await engine.syncOnce();

      expect(transport.pushes, hasLength(1));
      final payload = transport.pushes.single;
      expect(payload.notes, hasLength(1));
      expect(payload.notes.single['uuid'], uuid);
      expect(payload.notes.single['title'], 'Hello thread');
      expect(outbox.all(), completion(isEmpty));
    });

    test('deleted note is sent as a delete entry, then cleared', () async {
      final uuid = await notes.create(title: 'gone soon');
      await notes.delete(uuid);

      await engine.syncOnce();

      final payload = transport.pushes.single;
      expect(payload.deletes.single.type, 'notes');
      expect(payload.deletes.single.uuid, uuid);
      expect(outbox.all(), completion(isEmpty));
    });

    test('coalescing: two edits queue once as latest payload', () async {
      final uuid = await notes.create(title: 'v1');
      await notes.update(uuid, title: 'v2');
      expect(await outbox.all(), hasLength(1));

      await engine.syncOnce();
      expect(transport.pushes.single.notes.single['title'], 'v2');
    });

    test(
      'links and reminders push uuid references, never server ids',
      () async {
        final a = await notes.create(title: 'a');
        final b = await notes.create(title: 'b');
        final linkUuid = await links.link(
          sourceType: DaeItemType.note,
          sourceUuid: a,
          targetType: DaeItemType.note,
          targetUuid: b,
        );
        final reminders = RemindersRepository(db, outbox);
        final reminderUuid = await reminders.schedule(
          itemType: DaeItemType.note,
          itemUuid: a,
          title: 'ping',
          scheduledAt: DateTime.now(),
        );

        // Nothing to wait for: references are uuid-keyed, so the very first
        // cycle pushes the note, the link and the reminder together.
        await engine.syncOnce();

        final payload = transport.pushes.single;
        expect(payload.notes, hasLength(2));

        final pushedLink = payload.links.single;
        expect(pushedLink['uuid'], linkUuid);
        expect(pushedLink['source_uuid'], a);
        expect(pushedLink['target_uuid'], b);
        expect(pushedLink['source_type'], 'note');
        expect(pushedLink['target_type'], 'note');

        final pushedReminder = payload.reminders.single;
        expect(pushedReminder['uuid'], reminderUuid);
        expect(pushedReminder['item_uuid'], a);
        expect(pushedReminder['item_type'], 'note');

        expect(outbox.all(), completion(isEmpty));
      },
    );

    test(
      'link/reminder payloads are accepted straight from the queue',
      () async {
        // A link whose endpoints have never been pushed (nothing to resolve)
        // must still go out, because the server resolves uuid -> row itself.
        await outbox.queueUpsert(OutboxTable.links, 'link-1', {
          'uuid': 'link-1',
          'source_type': 'note',
          'source_uuid': 'never-synced-note',
          'target_type': 'todo',
          'target_uuid': 'never-synced-todo',
          'label': null,
          'updated_at': DateTime.utc(2026, 5, 5).toIso8601String(),
        });

        final payload = await engine.buildPushPayload();
        expect(payload.links, hasLength(1));
        expect(payload.links.single['source_uuid'], 'never-synced-note');
        expect(payload.links.single['target_uuid'], 'never-synced-todo');
      },
    );
  });

  group('conflict resolution (last-write-wins by updated_at)', () {
    test('newer server row wins: local adopts server, queue clears', () async {
      final uuid = await notes.create(title: 'local edit');
      final serverNewer = DateTime.now()
          .add(const Duration(minutes: 5))
          .toUtc();

      transport.pushHandler = (payload) => SyncPushResult(
        accepted: const [],
        conflicts: [
          SyncConflict(
            table: 'notes',
            uuid: uuid,
            serverRow: {
              'uuid': uuid,
              'id': 42,
              'title': 'server copy',
              'body': '',
              'pinned': false,
              'updated_at': serverNewer.toIso8601String(),
            },
          ),
        ],
      );

      await engine.syncOnce();

      final row = await notes.byUuid(uuid);
      expect(row?.title, 'server copy');
      expect(await outbox.all(), isEmpty);
    });

    test('newer local row wins: change stays queued for retry', () async {
      final uuid = await notes.create(title: 'fresh local');
      final serverOlder = DateTime.now()
          .subtract(const Duration(days: 1))
          .toUtc();

      transport.pushHandler = (payload) => SyncPushResult(
        accepted: const [],
        conflicts: [
          SyncConflict(
            table: 'notes',
            uuid: uuid,
            serverRow: {
              'uuid': uuid,
              'title': 'stale server',
              'updated_at': serverOlder.toIso8601String(),
            },
          ),
        ],
      );

      await engine.syncOnce();

      final row = await notes.byUuid(uuid);
      expect(row?.title, 'fresh local');
      expect(await outbox.all(), hasLength(1));
    });

    test('serverWins decision', () {
      final t = DateTime.utc(2026);
      expect(
        SyncEngine.serverWins(
          server: t.add(const Duration(seconds: 1)),
          local: t,
        ),
        isTrue,
      );
      expect(SyncEngine.serverWins(server: t, local: t), isFalse);
      expect(SyncEngine.serverWins(server: t, local: null), isTrue);
      expect(SyncEngine.serverWins(server: null, local: t), isFalse);
    });
  });

  group('pull', () {
    test(
      'server changes and tombstones are applied; cursor advances',
      () async {
        final localDoomed = await notes.create(title: 'doomed');

        transport.pullHandler = (since) => SyncPullResult(
          notes: [
            {
              'uuid': 'remote-1',
              'id': 7,
              'title': 'from server',
              'body': 'body',
              'pinned': false,
              'updated_at': DateTime.utc(2026, 5, 5).toIso8601String(),
            },
          ],
          todos: const [],
          links: const [],
          reminders: const [],
          deleted: {
            'notes': [localDoomed],
          },
          serverTime: DateTime.utc(2026, 5, 6),
        );

        await engine.syncOnce();

        expect(await notes.byUuid('remote-1'), isNotNull);
        final doomed = await notes.byUuid(localDoomed);
        expect(doomed?.deletedAt, isNotNull);
        expect(await db.readLastSyncedAt(), DateTime.utc(2026, 5, 6));

        // Next cycle sends the new cursor as `since`.
        await engine.syncOnce();
        expect(transport.pullCursors.last, DateTime.utc(2026, 5, 6));
      },
    );
  });

  group('network-aware retry', () {
    test('offline cycle short-circuits to offline state', () async {
      await notes.create(title: 'queued while offline');
      network.setOnline(false);

      await engine.syncWithRetry();

      expect(engine.current.phase, SyncPhase.offline);
      expect(transport.pushes, isEmpty);
    });

    test('failure backs off exponentially, succeeds on retry', () async {
      await notes.create(title: 'flaky');
      var failOnce = true;
      transport.pushHandler = (payload) {
        if (failOnce) {
          failOnce = false;
          throw Exception('boom');
        }
        return SyncPushResult(
          accepted: [
            SyncAccepted(
              table: 'notes',
              uuid: '${payload.notes.single['uuid']}',
            ),
          ],
          conflicts: const [],
        );
      };

      await engine.syncWithRetry();

      expect(engine.current.phase, SyncPhase.idle);
      expect(slept, [backoffDelay(0)]);
      expect(transport.pushes, hasLength(2));
      expect(outbox.all(), completion(isEmpty));
    });
  });

  test('status stream emits syncing then idle', () async {
    await notes.create(title: 'watch me');
    final phases = <SyncPhase>[];
    final sub = engine.status.listen((s) => phases.add(s.phase));
    await engine.syncOnce();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(phases, containsAllInOrder([SyncPhase.syncing, SyncPhase.idle]));
  });
}
