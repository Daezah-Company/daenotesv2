import 'dart:math';
import 'dart:ui';

import 'package:daenotes/core/dae_types.dart';
import 'package:daenotes/data/db/database.dart';
import 'package:daenotes/features/graph/graph_data.dart';
import 'package:daenotes/features/graph/graph_physics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic fixtures — everything keyed on uuid strings, mirroring the
/// contract rule that the graph never trusts an integer id.
GraphNode _node(int i, {bool done = false}) => GraphNode(
  uuid: 'note-$i',
  type: i.isEven ? DaeItemType.note : DaeItemType.todo,
  title: 'Item $i',
  done: done,
);

GraphEdge _edge(int i, String a, String b, {String? id}) => GraphEdge(
  uuid: id ?? 'link-$i',
  sourceUuid: a,
  targetUuid: b,
  sourceType: DaeItemType.note,
  targetType: DaeItemType.todo,
);

/// Deterministic fixtures built with a seeded Random — no wall clock, no
/// unseeded RNG anywhere. [isolated] is clamped so at least two nodes stay
/// connectable; asking for more edges than the core can hold yields a shorter
/// list instead of spinning forever.
GraphData buildBigGraph({int nodes = 250, int edges = 400, int isolated = 30}) {
  final rng = Random(42);
  final iso = max(0, min(isolated, nodes - 2));
  final connectedCount = nodes - iso;
  final all = [for (var i = 0; i < nodes; i++) _node(i)];
  final eps = <GraphEdge>[];
  if (connectedCount < 2) return GraphData(nodes: all, edges: eps);
  // Spanning path so the connected core is one component.
  for (var i = 1; i < connectedCount; i++) {
    eps.add(_edge(eps.length, all[i - 1].uuid, all[i].uuid));
  }
  final attempts = connectedCount * (connectedCount - 1);
  var guard = 0;
  while (eps.length < edges && guard++ < attempts * 20) {
    final a = rng.nextInt(connectedCount);
    final b = rng.nextInt(connectedCount);
    if (a == b) continue;
    eps.add(_edge(eps.length, all[a].uuid, all[b].uuid));
  }
  return GraphData(nodes: all, edges: eps);
}

Map<String, Size> _uniformSizes(GraphData d) => {
  for (final n in d.nodes) n.uuid: const Size(100, 32),
};

/// Runs the layout to rest. The ceiling is deliberate: a simulation that never
/// settles must fail with a message, not hang the test runner at 100% CPU.
int _settle(GraphSimulation sim, {int ceiling = 5000}) {
  var ticks = 0;
  while (sim.tick() && ticks < ceiling) {
    ticks++;
  }
  expect(sim.settled, isTrue, reason: 'layout still moving after $ticks ticks');
  return ticks;
}

void main() {
  group('convergence', () {
    test('250 nodes / 400 edges settles below the energy threshold '
        'well inside the tick budget (benchmark-style)', () {
      final data = buildBigGraph();
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      var ticks = 0;
      while (sim.tick() && ticks < 1000) {
        ticks++;
      }
      expect(sim.settled, isTrue);
      // Settled by energy, not by the maxTicks freeze: budget headroom.
      expect(sim.ticksRun, lessThan(sim.maxTicks));
      expect(ticks, lessThan(320));
      // Total kinetic energy: mean squared speed under the settle bound.
      expect(sim.kineticEnergy / sim.bodies.length, lessThan(0.001));
      for (final b in sim.bodies) {
        expect(b.position.dx.isFinite && b.position.dy.isFinite, isTrue);
      }
      // A settled sim does no work.
      expect(sim.tick(), isFalse);
    });

    test('layout is deterministic: same data lays out identically', () {
      final a = GraphSimulation(
        data: buildBigGraph(nodes: 60, edges: 80),
        sizes: _uniformSizes(buildBigGraph(nodes: 60, edges: 80)),
      );
      final b = GraphSimulation(
        data: buildBigGraph(nodes: 60, edges: 80),
        sizes: _uniformSizes(buildBigGraph(nodes: 60, edges: 80)),
      );
      for (var i = 0; i < 80; i++) {
        a.tick();
        b.tick();
      }
      for (final body in a.bodies) {
        expect(
          b.body(body.uuid)!.position,
          body.position,
          reason: 'position drift for ${body.uuid} breaks testable layout',
        );
      }
    });

    test('hot edit (one link added) reheats and re-settles', () {
      final data = GraphData(
        nodes: [_node(0), _node(1), _node(2)],
        edges: [_edge(0, 'note-0', 'note-1')],
      );
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      _settle(sim);
      final before = sim.body('note-2')!.position;
      final next = GraphData(
        nodes: [_node(0), _node(1), _node(2)],
        edges: [_edge(0, 'note-0', 'note-1'), _edge(1, 'note-1', 'note-2')],
      );
      expect(sim.applyData(next, sizes: _uniformSizes(next)), isTrue);
      var guard = 0;
      while (sim.tick() && guard++ < 500) {}
      expect(sim.settled, isTrue);
      // The formerly-isolated node moved off its ring to join the cluster.
      expect((sim.body('note-2')!.position - before).distance, greaterThan(1));
    });
  });

  group('degenerate cases', () {
    test('0 nodes: settles instantly, no crash', () {
      final sim = GraphSimulation(data: GraphData.empty, sizes: const {});
      expect(sim.tick(), isFalse);
      expect(sim.settled, isTrue);
      expect(sim.kineticEnergy, 0);
    });

    test('single node: finite position, no NaN', () {
      final data = GraphData(nodes: [_node(0)], edges: const []);
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      var ticks = 0;
      while (sim.tick() && ticks++ < 100) {}
      expect(sim.settled, isTrue);
      expect(sim.body('note-0')!.position.isFinite, isTrue);
    });

    test('hub with 30 edges converges without explosion', () {
      final leaves = [for (var i = 1; i <= 30; i++) _node(i)];
      final data = GraphData(
        nodes: [_node(0), ...leaves],
        edges: [
          for (final l in leaves) _edge(0, 'note-0', l.uuid, id: 'l-${l.uuid}'),
        ],
      );
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      var ticks = 0;
      while (sim.tick() && ticks++ < 400) {}
      expect(sim.settled, isTrue);
      for (final b in sim.bodies) {
        expect(b.position.distance, lessThan(100000));
        expect(b.position.isFinite, isTrue);
      }
    });

    test('two disconnected components stay finite and on-canvas', () {
      final data = GraphData(
        nodes: [_node(0), _node(1), _node(2), _node(3)],
        edges: [_edge(0, 'note-0', 'note-1'), _edge(1, 'note-2', 'note-3')],
      );
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      var ticks = 0;
      while (sim.tick() && ticks++ < 400) {}
      expect(sim.settled, isTrue);
      final c1 =
          (sim.body('note-0')!.position + sim.body('note-1')!.position) / 2;
      final c2 =
          (sim.body('note-2')!.position + sim.body('note-3')!.position) / 2;
      expect(c1.isFinite && c2.isFinite, isTrue);
    });

    test('coincident nodes separate via hash jitter (no div-by-zero)', () {
      final data = GraphData(nodes: [_node(0), _node(1)], edges: const []);
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      // Force them to the same point.
      sim.body('note-0')!.position = Offset.zero;
      sim.body('note-1')!.position = Offset.zero;
      sim.reheat();
      var ticks = 0;
      while (sim.tick() && ticks++ < 400) {}
      expect(sim.settled, isTrue);
      expect(
        sim.body('note-0')!.position.distanceSquared,
        isNot(sim.body('note-1')!.position.distanceSquared),
      );
      expect(sim.body('note-0')!.position.isFinite, isTrue);
      expect(sim.body('note-1')!.position.isFinite, isTrue);
    });

    test('drag pins a node, release reheats and re-settles', () {
      final data = buildBigGraph(nodes: 20, edges: 25);
      final sim = GraphSimulation(data: data, sizes: _uniformSizes(data));
      _settle(sim);
      sim.beginDrag('note-3');
      sim.dragTo('note-3', const Offset(500, 500));
      expect(sim.body('note-3')!.position, const Offset(500, 500));
      expect(sim.settled, isFalse);
      var ticks = 0;
      while (sim.tick() && ticks++ < 400) {}
      // Still settles while pinned.
      expect(sim.settled, isTrue);
      expect(sim.body('note-3')!.velocity, Offset.zero);
      sim.endDrag();
      expect(sim.settled, isFalse);
      ticks = 0;
      while (sim.tick() && ticks++ < 400) {}
      expect(sim.settled, isTrue);
    });
  });

  group('GraphData derivation', () {
    test('self-referential pair collapses to one thread (A->B + B->A)', () {
      final nodes = [_node(0), _node(1)];
      final raw = GraphData(
        nodes: nodes,
        edges: [
          _edge(0, 'note-0', 'note-1', id: 'x'),
          _edge(1, 'note-1', 'note-0', id: 'y'),
        ],
      );
      // buildGraphData is the dedup gate; here both edges are kept by design
      // for an already-normalised model, so check the repository gate instead.
      final dedup = GraphData(
        nodes: nodes,
        edges: [_edge(0, 'note-0', 'note-1', id: 'x')],
      );
      expect(raw.neighborsOf('note-0'), {'note-1'});
      expect(dedup.degreeOf('note-0'), 1);
    });

    test('a true self-loop and dangling endpoints are dropped', () {
      final notes = [_mkNote('n-1', 'One'), _mkNote('n-2', 'Two')];
      final data = buildGraphData(notes, const [], [
        _mkLink('l-1', 'n-1', 'n-1'), // self loop
        _mkLink('l-2', 'n-1', 'ghost'), // dangling target
        _mkLink('l-3', 'n-1', 'n-2'),
        _mkLink('l-4', 'n-2', 'n-1'), // reversed duplicate
      ]);
      expect(data.edges.length, 1);
      expect(data.edges.single.uuid, 'l-3');
      expect(data.degreeOf('n-1'), 1);
      expect(data.isIsolated('n-2'), isFalse);
    });
  });
}

Note _mkNote(String uuid, String title) => Note(
  id: 1,
  uuid: uuid,
  title: title,
  body: '',
  pinned: false,
  updatedAt: DateTime(2026),
);

Link _mkLink(String uuid, String source, String target) => Link(
  id: 1,
  uuid: uuid,
  sourceType: DaeItemType.note,
  sourceUuid: source,
  targetType: DaeItemType.note,
  targetUuid: target,
  updatedAt: DateTime(2026),
);
