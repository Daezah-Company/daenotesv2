import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/ds.dart';
import 'graph_measure.dart';
import 'graph_physics.dart';
import 'graph_view.dart';

/// Bichrome palette for the canvas chrome (contract §5): the only colour on
/// this surface is the thread palette and the sanctioned status/tone marks.
@immutable
class GraphPalette {
  const GraphPalette({
    required this.isDark,
    required this.canvas,
    required this.nodeFill,
    required this.onNode,
    required this.onNodeSecondary,
    required this.hairline,
    required this.selection,
  });

  final bool isDark;
  final Color canvas;
  final Color nodeFill;
  final Color onNode;
  final Color onNodeSecondary;
  final Color hairline;
  final Color selection;

  factory GraphPalette.of(DaeTokens t) => GraphPalette(
    isDark: t.isDark,
    canvas: t.background,
    nodeFill: t.isDark ? Ds.inkLift : Ds.paperVeil.withValues(alpha: 0.12),
    onNode: t.onSurface,
    onNodeSecondary: t.onSurfaceSecondary,
    hairline: t.hairline,
    selection: t.onSurface,
  );

  @override
  bool operator ==(Object other) =>
      other is GraphPalette &&
      other.isDark == isDark &&
      other.canvas == canvas &&
      other.nodeFill == nodeFill &&
      other.onNode == onNode &&
      other.onNodeSecondary == onNodeSecondary &&
      other.hairline == hairline &&
      other.selection == selection;

  @override
  int get hashCode => Object.hash(
    isDark,
    canvas,
    nodeFill,
    onNode,
    onNodeSecondary,
    hairline,
    selection,
  );
}

/// The whole scene is painted here: threads under, nodes over. Everything is
/// drawn in world space under the view matrix; viewport culling skips
/// off-screen nodes/edges so cost scales with what is *visible*, not with
/// total graph size.
class GraphCanvasPainter extends CustomPainter {
  GraphCanvasPainter({
    required this.sim,
    required this.view,
    required this.palette,
    required this.measurer,
    required this.reveal,
    required this.revealActive,
    required this.selectedUuid,
    required this.structuralKey,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GraphSimulation sim;
  final GraphViewController view;
  final GraphPalette palette;
  final GraphNodeMeasurer measurer;

  /// 0..1 choreography clock for the signature thread draw.
  final ValueListenable<double> reveal;
  final bool revealActive;
  final String? selectedUuid;

  /// Bumped whenever node/edge structure or theme changes; drives
  /// [shouldRepaint] for widget rebuilds (per-frame repaints arrive through
  /// the listenables without touching the widget tree).
  final int structuralKey;

  static const double _drawWindow =
      0.45; // fraction of the clock each edge takes
  static const double _maxStagger = 0.5; // last edge starts at 50%
  static const double _labelFullScale = 0.55;
  static const double _labelZeroScale = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    view.setViewport(size);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = palette.canvas,
    );

    if (sim.bodies.isEmpty) return;

    canvas.save();
    canvas.transform(view.transformStorage);
    final viewport = view.worldViewportRect();

    final t = revealActive ? reveal.value : 1.0;
    final selected = selectedUuid;
    final neighbors = selected == null
        ? const <String>{}
        : sim.data.neighborsOf(selected);

    _paintEdges(canvas, viewport, t, selected);
    _paintNodes(canvas, viewport, selected, neighbors);

    canvas.restore();
  }

  void _paintEdges(Canvas canvas, Rect viewport, double t, String? selected) {
    final edges = sim.data.edges;
    final last = math.max(edges.length - 1, 1);
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final a = sim.body(e.sourceUuid);
      final b = sim.body(e.targetUuid);
      if (a == null || b == null) continue;

      final p0 = a.position;
      final p1 = b.position;
      final span = Rect.fromPoints(p0, p1).inflate(60);
      if (!span.overlaps(viewport)) continue; // edge culling

      final delay = revealActive ? (i / last) * _maxStagger : 0.0;
      // Eased per edge: the thread shoots out then lands on the node, rather
      // than marching at a constant speed.
      final progress = revealActive
          ? DsMotion.enter.transform(
              ((t - delay) / _drawWindow).clamp(0.0, 1.0),
            )
          : 1.0;
      if (progress <= 0) continue;

      final delta = p1 - p0;
      final len2 = delta.distanceSquared;
      if (len2 < 1) continue; // degenerate overlap: nothing to draw
      final len = math.sqrt(len2);
      final normal = Offset(-delta.dy, delta.dx) / len;
      final bow = math.min(34.0, len * 0.16) * _edgeSide(e.uuid);
      final ctrl = (p0 + p1) / 2 + normal * bow;

      final touchesSelected =
          selected != null &&
          (e.sourceUuid == selected || e.targetUuid == selected);
      final paint = Paint()
        ..color = e.threadColor.withValues(
          alpha: selected == null
              ? 0.9
              : touchesSelected
              ? 1.0
              : 0.25,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = touchesSelected ? 2.4 : 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(_trimmedThread(p0, ctrl, p1, progress), paint);
    }
  }

  /// Deterministic curvature side per edge so reversed threads between the
  /// same pair bow apart instead of stacking.
  double _edgeSide(String uuid) =>
      (GraphSimulation.hashOf(uuid) & 1) == 0 ? 1 : -1;

  /// The signature "thread draw": trimming rebuilds the quadratic as a
  /// polyline over [0, progress] — the curve grows outward from the *source*
  /// node, matching the rail's top-down draw.
  Path _trimmedThread(Offset p0, Offset ctrl, Offset p1, double progress) {
    const steps = 18;
    final path = Path()..moveTo(p0.dx, p0.dy);
    if (progress >= 1) {
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, p1.dx, p1.dy);
      return path;
    }
    final n = math.max(2, (steps * progress).round());
    for (var k = 1; k <= n; k++) {
      final u = progress * k / n;
      final inv = 1 - u;
      final x = inv * inv * p0.dx + 2 * inv * u * ctrl.dx + u * u * p1.dx;
      final y = inv * inv * p0.dy + 2 * inv * u * ctrl.dy + u * u * p1.dy;
      path.lineTo(x, y);
    }
    return path;
  }

  void _paintNodes(
    Canvas canvas,
    Rect viewport,
    String? selected,
    Set<String> neighbors,
  ) {
    final fill = Paint()..color = palette.nodeFill;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final mark = Paint();

    // Labels fade out below the legibility threshold instead of shrinking
    // into mush; nodes stay readable rounded rects at any zoom.
    final scale = view.scale;
    final labelAlpha = scale >= _labelFullScale
        ? 1.0
        : ((scale - _labelZeroScale) / (_labelFullScale - _labelZeroScale))
              .clamp(0.0, 1.0);

    for (final node in sim.data.nodes) {
      final body = sim.body(node.uuid);
      if (body == null) continue;
      final rect = Rect.fromCenter(
        center: body.position,
        width: body.size.width,
        height: body.size.height,
      );
      if (!rect.overlaps(viewport)) continue; // node culling

      final isSelected = node.uuid == selected;
      final isNeighbor = neighbors.contains(node.uuid);
      final isolated = sim.data.isIsolated(node.uuid);
      final doneTodo = node.type == DaeItemType.todo && node.done;

      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(Ds.radiusSm + 2),
      );
      canvas.drawRRect(rrect, fill);

      stroke.color = isSelected
          ? palette.selection
          : palette.hairline.withValues(
              alpha: isNeighbor
                  ? 0.75
                  : isolated
                  ? 0.30
                  : 0.55,
            );
      stroke.strokeWidth = isSelected
          ? 2
          : isNeighbor
          ? 1.4
          : 1;
      canvas.drawRRect(rrect.inflate(isSelected ? 1 : 0.5), stroke);

      _paintTypeMark(canvas, rect, node.type, doneTodo, mark);

      if (labelAlpha > 0) {
        final tp = measurer.painterFor(
          node,
          tone: (isolated || doneTodo) ? 1 : 0,
        );
        final textOffset = Offset(
          rect.left + GraphNodeMeasurer.markSlot,
          rect.center.dy - tp.height / 2,
        );
        if (labelAlpha >= 1) {
          tp.paint(canvas, textOffset);
        } else {
          // Fade the label group without relayinging it — one layer per
          // visible node, alpha applied via a colour filter on the layer.
          canvas.saveLayer(
            rect,
            Paint()
              ..colorFilter = ColorFilter.matrix(<double>[
                1, 0, 0, 0, 0, //
                0, 1, 0, 0, 0, //
                0, 0, 1, 0, 0, //
                0, 0, 0, labelAlpha, 0, //
              ]),
          );
          tp.paint(canvas, textOffset);
          canvas.restore();
        }
        if (doneTodo) {
          // Status strike-through — status is a sanctioned emphasis; bichrome.
          final line = Paint()
            ..color = palette.onNodeSecondary
            ..strokeWidth = 1;
          final textRight = math.min(rect.right - 8, textOffset.dx + tp.width);
          canvas.drawLine(
            Offset(textOffset.dx, rect.center.dy),
            Offset(textRight, rect.center.dy),
            line,
          );
        }
      }
    }
  }

  /// note = filled square, todo = ring (filled when done). Shape carries the
  /// type distinction; solidity carries done-status — no colour on the mark.
  void _paintTypeMark(
    Canvas canvas,
    Rect rect,
    DaeItemType type,
    bool done,
    Paint paint,
  ) {
    final c = Offset(rect.left + 10, rect.center.dy);
    if (type == DaeItemType.note) {
      paint.color = done ? palette.onNodeSecondary : palette.onNode;
      paint.style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 7, height: 7),
          const Radius.circular(1.5),
        ),
        paint,
      );
    } else {
      paint.style = done ? PaintingStyle.fill : PaintingStyle.stroke;
      paint.strokeWidth = 1.5;
      paint.color = done ? palette.onNode : palette.onNodeSecondary;
      canvas.drawCircle(c, 3.6, paint);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(GraphCanvasPainter old) =>
      old.sim != sim ||
      old.view != view ||
      old.palette != palette ||
      old.measurer != measurer ||
      old.selectedUuid != selectedUuid ||
      old.revealActive != revealActive ||
      old.structuralKey != structuralKey;
}
