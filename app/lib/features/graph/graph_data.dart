import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../data/repos/links_repository.dart';
import '../../data/repos/notes_repository.dart';
import '../../data/repos/todos_repository.dart';

/// The pure graph model: identity is always the item `uuid` string
/// (contract §3) — never an integer id or a drift row id.
class GraphNode {
  const GraphNode({
    required this.uuid,
    required this.type,
    required this.title,
    this.done = false,
  });

  final String uuid;
  final DaeItemType type;
  final String title;

  /// Status for the type mark: only todos complete.
  final bool done;
}

/// One live link between two items. A self-referential pair
/// (A->B plus B->A) is two distinct edges; identity is the link uuid.
class GraphEdge {
  const GraphEdge({
    required this.uuid,
    required this.sourceUuid,
    required this.targetUuid,
    required this.sourceType,
    required this.targetType,
  });

  final String uuid;
  final String sourceUuid;
  final String targetUuid;
  final DaeItemType sourceType;
  final DaeItemType targetType;

  /// Exactly the colour the list spine's ThreadRail uses.
  Color get threadColor => Ds.threadColor(sourceType, targetType);
}

/// An immutable snapshot of every non-deleted item and every live link.
/// Built from the offline drift stores, so the graph needs no network.
class GraphData {
  GraphData({required this.nodes, required this.edges}) {
    for (final n in nodes) {
      byUuid[n.uuid] = n;
    }
    for (final e in edges) {
      _neighbors.putIfAbsent(e.sourceUuid, () => <String>{}).add(e.targetUuid);
      _neighbors.putIfAbsent(e.targetUuid, () => <String>{}).add(e.sourceUuid);
    }
  }

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final Map<String, GraphNode> byUuid = {};
  final Map<String, Set<String>> _neighbors = {};

  Set<String> neighborsOf(String uuid) => _neighbors[uuid] ?? const {};

  int degreeOf(String uuid) => _neighbors[uuid]?.length ?? 0;

  bool isIsolated(String uuid) => degreeOf(uuid) == 0;

  static final GraphData empty = GraphData(nodes: const [], edges: const []);
}

/// Builds the model from raw drift rows. Links whose endpoints are not (both)
/// live items are dropped; links with an unknown endpoint type resolve through
/// the node map when possible.
GraphData buildGraphData(List<Note> notes, List<Todo> todos, List<Link> links) {
  final nodes = <GraphNode>[
    for (final n in notes)
      GraphNode(
        uuid: n.uuid,
        type: DaeItemType.note,
        title: n.title.trim().isEmpty ? '(tanpa judul)' : n.title.trim(),
      ),
    for (final t in todos)
      GraphNode(
        uuid: t.uuid,
        type: DaeItemType.todo,
        title: t.title.trim().isEmpty ? '(tanpa judul)' : t.title.trim(),
        done: t.done,
      ),
  ];
  final index = {for (final n in nodes) n.uuid: n};

  final edges = <GraphEdge>[];
  final seenPairs = <String>{};
  for (final l in links) {
    final s = index[l.sourceUuid];
    final t = index[l.targetUuid];
    if (s == null || t == null) continue; // dangling link — ignore
    if (l.sourceUuid == l.targetUuid) continue; // self loop: no thread to draw
    final key = l.sourceUuid.compareTo(l.targetUuid) < 0
        ? '${l.sourceUuid}\u0000${l.targetUuid}'
        : '${l.targetUuid}\u0000${l.sourceUuid}';
    if (!seenPairs.add(key)) continue; // collapse A->B + B->A into one thread
    edges.add(
      GraphEdge(
        uuid: l.uuid,
        sourceUuid: l.sourceUuid,
        targetUuid: l.targetUuid,
        sourceType: s.type,
        targetType: t.type,
      ),
    );
  }
  return GraphData(nodes: nodes, edges: edges);
}

/// Combined live model stream: all non-deleted notes + todos + all live
/// links, re-emitted whenever any of the three watch streams fire.
Stream<GraphData> graphModelStream({
  required NotesRepository notes,
  required TodosRepository todos,
  required LinksRepository links,
}) {
  late final StreamController<GraphData> out;
  StreamSubscription<List<Note>>? sn;
  StreamSubscription<List<Todo>>? st;
  StreamSubscription<List<Link>>? sl;
  List<Note>? latestNotes;
  List<Todo>? latestTodos;
  List<Link>? latestLinks;

  void emit() {
    final n = latestNotes, t = latestTodos, l = latestLinks;
    if (n != null && t != null && l != null) {
      out.add(buildGraphData(n, t, l));
    }
  }

  out = StreamController<GraphData>(
    onListen: () {
      sn = notes.watchNotes(archived: true).listen((v) {
        latestNotes = v;
        emit();
      }, onError: (Object e, StackTrace s) => out.addError(e, s));
      st = todos.watchTodos(archived: true).listen((v) {
        latestTodos = v;
        emit();
      }, onError: (Object e, StackTrace s) => out.addError(e, s));
      sl = links.watchAllLinks().listen((v) {
        latestLinks = v;
        emit();
      }, onError: (Object e, StackTrace s) => out.addError(e, s));
    },
    onCancel: () async {
      await sn?.cancel();
      await st?.cancel();
      await sl?.cancel();
    },
  );
  return out.stream;
}

/// Live offline graph model. Features watch this, never the raw tables.
final graphDataProvider = StreamProvider<GraphData>((ref) {
  return graphModelStream(
    notes: ref.watch(notesRepositoryProvider),
    todos: ref.watch(todosRepositoryProvider),
    links: ref.watch(linksRepositoryProvider),
  );
});
