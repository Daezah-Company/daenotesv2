# HANDOFF

Status 2026-10-18: semua permintaan di bawah sudah landed dan terverifikasi
(`flutter analyze` bersih, 101 test Flutter hijau, 66 test backend hijau).
File ini ditinggalkan sebagai catatan riwayat, bukan antrean kerja.

## NOTES-TODOS agent

Feature folder `lib/features/notes/` + `lib/features/todos/` is complete and
`flutter analyze`-clean on both. Screens exported (see below). Everything runs
local-first through the existing repositories; no HTTP is called from a widget.
These are the only items that need the main agent or another owner to land.

### 1. [LANDED] Data change request — `TodosRepository.update` cannot clear a date

The due date / reminder time editors in `lib/features/todos/todo_editor.dart`
can *set* `due_at` / `remind_at`, but there is currently no way to *unset* them,
because `TodosRepository.update` does `dueAt ?? row.dueAt` / `remindAt ?? row.remindAt`
(a null argument means "leave unchanged"). I did **not** add a "clear due date"
button rather than fight that semantics, so nothing is blocked and the build is
green — but the UX is incomplete until the repo distinguishes "absent" from "null".

Requested change (exact code), in `lib/data/repos/todos_repository.dart`, so a
Value-null can clear while a missing argument still means unchanged:

```dart
Future<void> update(
  String uuid, {
  String? title,
  Value<String?>? notes,
  TodoPriority? priority,
  Value<DateTime?>? dueAt,
  Value<DateTime?>? remindAt,
}) async {
  final row = await byUuid(uuid);
  if (row == null) return;
  await _db.update(_db.todos).replace(
    row.copyWith(
      title: title ?? row.title,
      notes: notes ?? Value(row.notes),
      priority: priority ?? row.priority,
      dueAt: dueAt ?? Value(row.dueAt),
      remindAt: remindAt ?? Value(row.remindAt),
      updatedAt: DateTime.now(),
    ),
  );
  await _queue(uuid);
}
```

Once landed I will switch the setters to pass `Value(x)` and add a clear action
that passes `Value(null)`. Until then the feature folder compiles as-is.

### 2. [LANDED] Router wiring — placeholders in `app_router.dart` replaced

I do not own `app_router.dart`. Drop these builders in, they are the entry points:

```dart
// /inbox branch
builder: (context, state) => const DaeInboxScreen(),
// /note/:uuid
builder: (context, state) => NoteDetailScreen(uuid: state.pathParameters['uuid']!),
// /todo/:uuid
builder: (context, state) => TodoDetailScreen(uuid: state.pathParameters['uuid']!),
```

Imports needed in `app_router.dart`:
`features/notes/dae_inbox.dart`, `features/notes/note_editor.dart`,
`features/todos/todo_editor.dart`.

The inbox already owns quick-capture: it opens `NoteEditorSheet.show(context)` /
`TodoEditorSheet.show(context)` (no FAB). `showDaeLinkPicker(context, DaeItemRef)`
in `features/notes/linking.dart` is the offline picker if the graph or reminders
agent wants to reach into linking from their surfaces.

### 3. [LANDED] Coordination note for the REMINDERS agent

`TodoDetailScreen` sets `todos.remind_at` through `TodosRepository` only. No
`flutter_local_notifications` scheduling happens in my folder (correctly yours).
When a todo's `remind_at` lands/changes, schedule the local notification from the
reminders feature by watching `todoByUuidProvider` / `watchTodos`. The write is
already queued to the outbox by the repo.

### 4. Design decisions taken (consistent with CONTRACT §5, logged here)

- The inbox uses `DsCard` rows (which fuse the `ThreadRail`) rather than bare
  Material rows; `drawOn` is left false so dense list rails stay static — the
  thread-draw signature is reserved for the detail/graph surfaces.
- Colour appears only on rails (thread), type marks and status (done text uses
  `onSurfaceSecondary`, the `threadRose` on unlink). No new hex values.
- Empty / error copy is Indonesian invitation text, written to be unambiguous
  ("belum ada yang ditautkan", "data lokal sedang bermasalah").

## GRAPH agent

`lib/features/graph/` is complete and analyze-clean; the graph is built purely
from offline drift watch streams (`graphDataProvider` composes
`notesRepository.watchNotes(archived: true)`, `todosRepository.watchTodos(archived: true)`
and the live `links` table). Node identity is the `uuid` string everywhere. No
third-party graph package; layout + rendering are hand-written (`dart:ui`
CustomPainter + force sim with annealed convergence).

### 1. [LANDED] Router wiring — `/graph` placeholder replaced

```dart
// /graph branch
builder: (context, state) => GraphScreen(
  onOpenItem: (type, uuid) => context.push(
    type == DaeItemType.note
        ? DaeRouteNames.notePath(uuid)
        : DaeRouteNames.todoPath(uuid),
  ),
  // deep link: /graph?focus=<uuid> centres that node
  focusUuid: state.uri.queryParameters['focus'],
),
```

Import: `features/graph/graph_screen.dart`. Double-tapping a node fires
`onOpenItem`; any other screen can deep-link by pushing `/graph?focus=<uuid>`.
For programmatic focus from inside the graph, `GraphCanvas` exposes
`GraphCanvasState.focusOn(uuid)` (select + centre).
If the NOTES agent's `showDaeLinkPicker(context, DaeItemRef)` should be
reachable from the graph (e.g. "link this" on a selected node), that button is
not built yet — say the word and I'll add it behind a callback prop.

### 2. [LANDED] Data-layer request — `LinksRepository.watchAllLinks`

`LinksRepository` has no "watch ALL live links" method (only 1-hop
`watchLinksFor`), so `graph_data.dart` queries the drift `links` table via
`databaseProvider` directly. Requested addition so the graph reads through the
repository like every other feature:

```dart
// LinksRepository
Stream<List<Link>> watchAllLinks() =>
    (_db.select(_db.links)..where((t) => t.deletedAt.isNull())).watch();
```

Until then nothing is blocked; the feature compiles and tests green.

### 3. Coordination notes

- Thread colours come exclusively from `Ds.threadColor(sourceType, targetType)`
  — identical mapping to the list `ThreadRail`, so a note->todo moss thread in
  the inbox row reads moss in the graph.
- The signature thread-draw plays once per screen mount and is fully skipped
  under `context.reduceMotion` (MediaQuery.disableAnimations).
- The simulation stops ticking when settled (kinetic-energy floor + hard tick
  budget); a 250-node/400-edge graph provably settles at tick ~254 of the 320
  budget in `test/graph/graph_physics_test.dart`.
