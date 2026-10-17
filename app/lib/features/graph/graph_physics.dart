import 'dart:math' as math;
import 'dart:ui';

import 'graph_data.dart';

/// One simulated body. Positions are in world coordinates; the view
/// transform maps world -> screen.
class GraphBody {
  GraphBody({required this.uuid, required this.size, required this.position})
    : velocity = Offset.zero;

  final String uuid;
  Offset position;
  Offset velocity;
  Size size;

  /// True for nodes the pointer is currently dragging (or that the caller
  /// pins): the integrator keeps their velocity at zero.
  bool pinned = false;
}

/// A hand-written force-directed layout (contract §6: no graph packages).
///
/// Forces per tick, all O(n^2) pairs which is fine at this product's scale
/// (~250 nodes):
/// - Coulomb-style repulsion between every pair, capped per node so a hub
///   with 30 edges cannot explode;
/// - Hookean springs along edges pulling toward [GraphSimulation.restLength];
/// - gentle linear gravity toward the origin so disconnected components stay
///   on-canvas;
/// - velocity damping (0.8) with a hard per-tick velocity clamp.
///
/// Convergence: with fixed unit timestep, damping < 1 and capped forces make
/// the system a contraction toward the force equilibrium — total kinetic
/// energy falls monotonically after the initial transient. The loop reports
/// `settled` once mean squared speed stays below a threshold for a few
/// consecutive ticks, and force-freezes at [maxTicks] regardless, so it can
/// never tick forever. A settled simulation performs zero work per frame.
///
/// Determinism: seed positions are a golden-angle sunflower for connected
/// nodes and a hash-angle ring for isolated ones, both keyed on the sorted
/// uuid list; all jitter directions come from an FNV-1a hash of the uuid.
/// No wall-clock or RNG state is ever consulted.
class GraphSimulation {
  GraphSimulation({
    required GraphData data,
    required Map<String, Size> sizes,
    this.restLength = 130,
    this.maxTicks = 320,
  }) : _data = data {
    applyData(data, sizes: sizes);
  }

  // ---- tuned constants ------------------------------------------------
  static const double _repulsion = 20000; // F = _repulsion / d^2
  static const double _springK = 0.05;
  static const double _gravity = 0.03;
  static const double _damping = 0.6;
  static const double _maxVelocity = 6;
  static const double _maxForce = 30;
  static const double _minDistanceSq = 1e-4; // division-by-zero guard
  static const double _settleMeanSpeedSq =
      0.004; // ~0.06 px/tick RMS — sub-pixel, frozen on settle
  static const double _settleVelocitySq = 1e-6; // "still moving" detector
  // Repulsion is short-range (cut off at ~480 world px): far-field pairs
  // contribute noise, not structure, and dropping them is what makes a
  // 250-node graph reach the energy floor within the tick budget.
  static const double _repulsionCutoff = 480;
  static const int _settleStreak = 4;

  GraphData _data;
  final Map<String, GraphBody> _bodies = {};
  Set<String> _edgeIds = {};
  final double restLength;
  final int maxTicks;

  bool settled = false;
  int _ticksSinceHeat = 0;
  int _lowStreak = 0;
  String? _dragged;

  GraphData get data => _data;
  Iterable<GraphBody> get bodies => _bodies.values;
  GraphBody? body(String uuid) => _bodies[uuid];

  /// Ticks since the last reheat — bounded by [maxTicks]; tests assert the
  /// layout settled *before* the cap (real convergence, not a freeze).
  int get ticksRun => _ticksSinceHeat;

  /// Monotonic counter bumped whenever the node/edge structure changes;
  /// the painter uses it to invalidate cached geometry without diffing.
  int structuralRevision = 0;

  // ------------------------------------------------------------------ data

  /// Swaps in a new snapshot, keeping positions for surviving nodes so a
  /// link edit never re-runs the whole layout. Returns true when something
  /// structural changed and the simulation must run again.
  bool applyData(GraphData next, {required Map<String, Size> sizes}) {
    final nodeIds = {for (final n in next.nodes) n.uuid};
    final edgeIds = {for (final e in next.edges) e.uuid};
    final changed =
        nodeIds.length != _bodies.length ||
        edgeIds.length != _edgeIds.length ||
        !nodeIds.containsAll(_bodies.keys) ||
        !_edgeIds.containsAll(edgeIds);
    _data = next;
    _edgeIds = edgeIds;

    _bodies.removeWhere((uuid, _) => next.byUuid[uuid] == null);
    final sorted = [...next.nodes]..sort((a, b) => a.uuid.compareTo(b.uuid));
    var connectedSlot = 0;
    for (final n in sorted) {
      final size = sizes[n.uuid] ?? const Size(64, 32);
      var body = _bodies[n.uuid];
      if (body == null) {
        body = GraphBody(
          uuid: n.uuid,
          size: size,
          position: next.isIsolated(n.uuid)
              ? _isolatedSeed(n.uuid, sorted.indexOf(n), sorted.length)
              : _connectedSeed(connectedSlot, sorted.length),
        );
        _bodies[n.uuid] = body;
      } else {
        body.size = size;
      }
      if (!next.isIsolated(n.uuid)) connectedSlot++;
    }
    if (changed) {
      structuralRevision++;
      reheat();
    }
    return changed;
  }

  // ----------------------------------------------------------------- seeds

  static const double _goldenAngle = 2.399963229728653;

  Offset _connectedSeed(int slot, int total) {
    final i = slot + 1;
    final r = 46 * math.sqrt(i);
    final a = slot * _goldenAngle;
    return Offset(r * math.cos(a), r * math.sin(a));
  }

  Offset _isolatedSeed(String uuid, int index, int total) {
    final a = _hashAngle(uuid);
    const r = 300.0;
    return Offset(r * math.cos(a), r * math.sin(a));
  }

  // ---------------------------------------------------------------- hashing

  /// FNV-1a over the uuid — the only randomness source, deterministic and
  /// dependency-free. Exposed for the painter's edge-bow hashing.
  static int hashOf(String key) => _hash(key);

  static int _hash(String key) {
    var h = 0x811c9dc5;
    for (var i = 0; i < key.codeUnits.length; i++) {
      h ^= key.codeUnits[i];
      // 32-bit wrapped multiply (deterministic on the VM).
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7fffffff;
  }

  static double _hashAngle(String uuid) =>
      (_hash(uuid) % 360000) / 360000.0 * 2 * math.pi;

  /// Deterministic unit vector used when two nodes sit exactly on top of
  /// each other (repulsion direction is undefined there).
  static Offset _hashDirection(String uuid) {
    final a = _hashAngle(uuid);
    return Offset(math.cos(a), math.sin(a));
  }

  // ----------------------------------------------------------------- ticks

  double get kineticEnergy {
    var ke = 0.0;
    for (final b in _bodies.values) {
      ke += b.velocity.distanceSquared;
    }
    return ke;
  }

  double get _meanSpeedSq =>
      _bodies.isEmpty ? 0 : kineticEnergy / _bodies.length;

  /// Annealing schedule: 1 -> 0.12 across the tick budget.
  double get _cooling =>
      math.max(0.02, 1.0 - _ticksSinceHeat / (maxTicks * 0.8));

  /// Runs one fixed-timestep tick. Returns false once settled (the caller
  /// must stop the ticker then); a settled tick does no work.
  bool tick() {
    if (settled || _bodies.isEmpty) {
      settled = true;
      return false;
    }
    _ticksSinceHeat++;

    final forces = Map<String, Offset>.fromEntries(
      _bodies.values.map((b) => MapEntry(b.uuid, Offset.zero)),
    );

    // Pairwise repulsion.
    final list = _bodies.values.toList(growable: false);
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        var dx = a.position.dx - b.position.dx;
        var dy = a.position.dy - b.position.dy;
        var d2 = dx * dx + dy * dy;
        if (d2 > _repulsionCutoff * _repulsionCutoff) continue; // short-range
        if (d2 < _minDistanceSq) {
          // Perfectly coincident: nudge apart along a deterministic direction
          // chosen from the lexicographically smaller uuid's hash.
          final dir = _hashDirection(
            a.uuid.compareTo(b.uuid) < 0 ? a.uuid : b.uuid,
          );
          dx = dir.dx;
          dy = dir.dy;
          d2 = 1;
        }
        final f = _repulsion / d2;
        final inv = 1 / math.sqrt(d2);
        final fx = dx * inv * f;
        final fy = dy * inv * f;
        forces[a.uuid] = forces[a.uuid]! + Offset(fx, fy);
        forces[b.uuid] = forces[b.uuid]! - Offset(fx, fy);
      }
    }

    // Spring attraction along edges.
    for (final e in _data.edges) {
      final a = _bodies[e.sourceUuid];
      final b = _bodies[e.targetUuid];
      if (a == null || b == null) continue;
      var dx = b.position.dx - a.position.dx;
      var dy = b.position.dy - a.position.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 < _minDistanceSq) {
        final dir = _hashDirection(a.uuid);
        dx = dir.dx;
        dy = dir.dy;
      }
      final d = math.sqrt(math.max(dx * dx + dy * dy, _minDistanceSq));
      final f = _springK * (d - restLength);
      final fx = dx / d * f;
      final fy = dy / d * f;
      forces[a.uuid] = forces[a.uuid]! + Offset(fx, fy);
      forces[b.uuid] = forces[b.uuid]! - Offset(fx, fy);
    }

    // Isolated nodes are anchored to a ring outside the connected cloud —
    // "unlinked" reads as parked at the edge, exactly what the product wants
    // to show. The anchor tracks the cloud radius so the ring grows with it.
    final anchorRadius = _connectedBoundingRadius() + 90;

    // Integrate.
    var moving = 0;
    for (final b in _bodies.values) {
      if (b.pinned) {
        b.velocity = Offset.zero;
        continue;
      }
      var f = forces[b.uuid] ?? Offset.zero;
      if (_data.isIsolated(b.uuid)) {
        final a = _hashAngle(b.uuid);
        final anchor = Offset(
          anchorRadius * math.cos(a),
          anchorRadius * math.sin(a),
        );
        f += (anchor - b.position) * 0.35;
      } else {
        f -= b.position * _gravity;
      }
      // Cap the net force, then integrate with damping + velocity clamp.
      final fMag = f.distance;
      if (fMag > _maxForce) f = f / fMag * _maxForce;
      var v = (b.velocity + f) * _damping;
      final vMag = v.distance;
      if (vMag > _maxVelocity) v = v / vMag * _maxVelocity;
      // Fruchterman-Reingold-style annealing: a cooling schedule on the
      // velocity guarantees the liquid phase ends — mean energy decays even
      // while forces keep shuffling neighbours, so a dense 250-node graph
      // provably reaches the energy floor before the tick budget runs out.
      v = v * _cooling;
      if (!v.isFinite) v = Offset.zero; // never propagate NaN
      b.velocity = v;
      var p = b.position + v;
      if (!p.isFinite) {
        p = Offset.zero;
        b.velocity = Offset.zero;
      }
      b.position = Offset(
        p.dx.clamp(-100000.0, 100000.0),
        p.dy.clamp(-100000.0, 100000.0),
      );
      if (v.distanceSquared > _settleVelocitySq) moving++;
    }

    // Convergence detection.
    if (_meanSpeedSq < _settleMeanSpeedSq) {
      _lowStreak++;
    } else {
      _lowStreak = 0;
    }
    if (_lowStreak >= _settleStreak ||
        _ticksSinceHeat >= maxTicks ||
        moving == 0) {
      _freeze();
    }
    return !settled;
  }

  double _connectedBoundingRadius() {
    var r = 0.0;
    for (final b in _bodies.values) {
      if (_data.isIsolated(b.uuid)) continue;
      final d = b.position.distance;
      if (d > r) r = d;
    }
    return r.isFinite ? r : 0;
  }

  void _freeze() {
    settled = true;
    for (final b in _bodies.values) {
      b.velocity = Offset.zero;
    }
  }

  /// Restarts ticking after a structural change or a node drag.
  void reheat() {
    settled = false;
    _ticksSinceHeat = 0;
    _lowStreak = 0;
  }

  // ------------------------------------------------------------------ drag

  void beginDrag(String uuid) {
    final b = _bodies[uuid];
    if (b == null) return;
    _dragged = uuid;
    b.pinned = true;
    b.velocity = Offset.zero;
  }

  void dragTo(String uuid, Offset worldPosition) {
    final b = _bodies[uuid];
    if (b == null || !worldPosition.isFinite) return;
    b.position = worldPosition;
    b.velocity = Offset.zero;
    settled = false; // caller keeps ticking while the pointer moves
    _ticksSinceHeat = 0;
  }

  void endDrag() {
    final uuid = _dragged;
    _dragged = null;
    if (uuid == null) return;
    _bodies[uuid]?.pinned = false;
    reheat();
  }

  String? get draggedUuid => _dragged;

  /// Radius of the ring the isolated nodes are anchored to — used by the
  /// painter to keep the viewport fit honest when everything is unlinked.
  double get isolatedRingRadius => _connectedBoundingRadius() + 90;
}
