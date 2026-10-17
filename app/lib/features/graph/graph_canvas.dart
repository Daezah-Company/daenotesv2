import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import 'graph_data.dart';
import 'graph_measure.dart';
import 'graph_painter.dart';
import 'graph_physics.dart';
import 'graph_view.dart';

/// Called when the user double-taps a node (or asks to open it from the
/// selection panel). The router owner maps (type, uuid) to a route — this
/// feature never touches navigation itself.
typedef GraphItemOpenCallback = void Function(DaeItemType type, String uuid);

/// The interactive graph surface: offline-driven force layout, CustomPainter
/// rendering, pan/pinch/drag/tap gestures, the staggered thread-draw reveal,
/// and per-node Semantics. Embed anywhere; [GraphScreen] is the page shell.
class GraphCanvas extends ConsumerStatefulWidget {
  const GraphCanvas({super.key, this.onOpenItem, this.focusUuid});

  /// Deep-link callback for item open (wired to the router by the app shell).
  final GraphItemOpenCallback? onOpenItem;

  /// When non-null, the canvas centres that node once the layout is live.
  final String? focusUuid;

  @override
  ConsumerState<GraphCanvas> createState() => GraphCanvasState();
}

@visibleForTesting
class GraphCanvasState extends ConsumerState<GraphCanvas>
    with TickerProviderStateMixin {
  static const Duration _revealDuration = DsMotion.canvasReveal;
  static const Duration _focusDuration = DsMotion.focusPan;

  final GraphViewController view = GraphViewController();

  /// Repaint signal for simulation ticks (the widget tree does NOT rebuild).
  final ValueNotifier<int> simTick = ValueNotifier<int>(0);

  /// Choreography clock value (0..1) read by the painter each frame.
  final ValueNotifier<double> revealValue = ValueNotifier<double>(0);

  /// Bumped on structural data changes + on settle — drives the semantics
  /// layer without rebuilding it every tick.
  final ValueNotifier<int> structureVersion = ValueNotifier<int>(0);

  /// Merged repaint source handed to the painter (this render stack drives
  /// repaints through `CustomPainter(repaint:)`, not the widget param).
  late final Listenable repaint;

  GraphSimulation? sim;
  GraphNodeMeasurer? measurer;
  GraphPalette? palette;

  late final Ticker _simTicker;
  late final AnimationController _revealCtrl;
  AnimationController? _focusCtrl;
  Offset? _focusFromTranslation;
  double? _focusFromScale;
  Offset? _focusToTranslation;
  double? _focusToScale;

  bool revealActive = false;
  bool _revealPlayed = false;
  bool _fittedOnce = false;
  int _structuralKey = 0;
  String? selectedUuid;

  // ---- pointer bookkeeping ------------------------------------------------
  final Map<int, Offset> _pointers = {};
  _TouchMode _mode = _TouchMode.none;
  String? _dragNode;
  Offset _singleBase = Offset.zero;
  Offset _pinchMid = Offset.zero;
  double _pinchDist = 0;
  double _movedDistance = 0;
  Offset _doubleTapAt = Offset.zero;

  bool get _reducedMotion => context.reduceMotion;

  @override
  void initState() {
    super.initState();
    repaint = Listenable.merge([simTick, revealValue, view]);
    _simTicker = createTicker((_) {
      final s = sim;
      if (s == null) return;
      if (!s.tick()) {
        _simTicker.stop();
        structureVersion.value++; // refresh semantics rects once, not per frame
      }
      simTick.value++;
    });
    _revealCtrl = AnimationController(vsync: this, duration: _revealDuration)
      ..addListener(() => revealValue.value = _revealCtrl.value);
    _revealCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && revealActive) {
        setState(() => revealActive = false);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    measurer = GraphNodeMeasurer.of(context);
    palette = GraphPalette.of(context.dae);
  }

  @override
  void dispose() {
    _simTicker.dispose();
    _revealCtrl.dispose();
    _focusCtrl?.dispose();
    view.dispose();
    simTick.dispose();
    revealValue.dispose();
    structureVersion.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------- data

  Map<String, Size> _sizesFor(GraphData data) {
    final m = measurer;
    if (m == null) return const {};
    return {for (final n in data.nodes) n.uuid: m.sizeFor(n)};
  }

  /// Ingests a snapshot from the watch streams. Idempotent — called from
  /// build with the latest provider value; sim objects are preserved across
  /// emissions so layout history (and determinism) survives live edits.
  void _ingest(GraphData? data) {
    if (data == null) return;
    var s = sim;
    if (s == null) {
      s = GraphSimulation(data: data, sizes: _sizesFor(data));
      sim = s;
      _structuralKey++;
      structureVersion.value++;
      if (data.nodes.isNotEmpty) {
        final created = s;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitAndReveal(created);
        });
      } else {
        _revealPlayed = true; // empty graph has nothing to draw on
      }
    } else {
      final changed = s.applyData(data, sizes: _sizesFor(data));
      if (changed) {
        _structuralKey++;
        structureVersion.value++;
      }
      if (selectedUuid != null && data.byUuid[selectedUuid] == null) {
        selectedUuid = null;
      }
    }
    if (!s.settled) _ensureTicking();
  }

  void _fitAndReveal(GraphSimulation s) {
    if (!_fittedOnce && s.bodies.isNotEmpty) {
      _fittedOnce = true;
      view.fitContent(math.max(s.isolatedRingRadius, 160), view.viewport);
    }
    _startReveal();
    _ensureTicking();
    _maybeFocusFromWidget(s);
  }

  void _startReveal() {
    if (_revealPlayed) return;
    _revealPlayed = true;
    if (_reducedMotion) {
      revealValue.value = 1;
      revealActive = false; // straight to final state — no draw-on
      return;
    }
    setState(() => revealActive = true);
    _revealCtrl.forward();
  }

  void _ensureTicking() {
    final s = sim;
    if (s == null || s.settled) return;
    if (!_simTicker.isActive) _simTicker.start();
  }

  void _maybeFocusFromWidget(GraphSimulation s) {
    final uuid = widget.focusUuid;
    if (uuid == null) return;
    if (s.body(uuid) != null) focusOn(uuid);
  }

  // ---------------------------------------------------------------- gestures

  Offset _local(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return global;
    return box.globalToLocal(global);
  }

  /// Topmost node at a *canvas-local* screen point, or null.
  String? _hitTest(Offset screenPos) {
    final s = sim;
    if (s == null) return null;
    final world = view.screenToWorld(screenPos);
    final nodes = s.data.nodes;
    for (var i = nodes.length - 1; i >= 0; i--) {
      final n = nodes[i];
      final b = s.body(n.uuid);
      if (b == null) continue;
      final rect = Rect.fromCenter(
        center: b.position,
        width: b.size.width,
        height: b.size.height,
      ).inflate(6);
      if (rect.contains(world)) return n.uuid;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _singleBase = e.localPosition;
      _movedDistance = 0;
      final hit = _hitTest(e.localPosition);
      if (hit != null) {
        _mode = _TouchMode.nodeDrag;
        _dragNode = hit;
        sim?.beginDrag(hit);
        _ensureTicking();
      } else {
        _mode = _TouchMode.pan;
      }
    } else if (_pointers.length == 2) {
      // Second finger: a node drag hands over to pinch — canvas transform.
      if (_mode == _TouchMode.nodeDrag && _dragNode != null) {
        sim?.endDrag();
        _dragNode = null;
      }
      _mode = _TouchMode.pinch;
      final vals = _pointers.values.toList(growable: false);
      _pinchMid = (vals[0] + vals[1]) / 2;
      _pinchDist = (vals[0] - vals[1]).distance;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    switch (_mode) {
      case _TouchMode.nodeDrag:
        final uuid = _dragNode;
        if (uuid != null) {
          _movedDistance += (e.localPosition - _singleBase).distance;
          sim?.dragTo(uuid, view.screenToWorld(e.localPosition));
          _singleBase = e.localPosition;
          _ensureTicking();
          simTick.value++;
        }
      case _TouchMode.pan:
        final delta = e.localPosition - _singleBase;
        _movedDistance += delta.distance;
        view.panBy(delta);
        _singleBase = e.localPosition;
      case _TouchMode.pinch:
        final vals = _pointers.values.toList(growable: false);
        if (vals.length < 2) break;
        final mid = (vals[0] + vals[1]) / 2;
        final dist = (vals[0] - vals[1]).distance;
        if (_pinchDist > 1 && dist > 1 && mid.isFinite) {
          view.zoomBy(dist / _pinchDist, mid);
          view.panBy(mid - _pinchMid);
        }
        _pinchMid = mid;
        _pinchDist = dist;
      case _TouchMode.none:
        break;
    }
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      if (_mode == _TouchMode.nodeDrag && _dragNode != null) {
        sim?.endDrag();
        _dragNode = null;
        _ensureTicking();
      }
      _mode = _TouchMode.none;
    } else if (_pointers.length == 1 && _mode == _TouchMode.pinch) {
      _mode = _TouchMode.pan;
      _singleBase = _pointers.values.first;
    }
  }

  void _handleTap(Offset globalPos) {
    if (_movedDistance > 18) return; // that was a pan/drag
    final hit = _hitTest(_local(globalPos));
    setState(() => selectedUuid = hit);
  }

  void _handleDoubleTap() {
    final s = sim;
    if (s == null) return;
    final hit = _hitTest(_local(_doubleTapAt));
    if (hit == null) return;
    final node = s.data.byUuid[hit];
    if (node == null) return;
    setState(() => selectedUuid = hit);
    widget.onOpenItem?.call(node.type, node.uuid);
  }

  // -------------------------------------------------------------------- api

  /// Selects a node programmatically (semantics layer, tests, deep links).
  void select(String? uuid) => setState(() => selectedUuid = uuid);

  /// Deep-link entry point: centre [uuid] in the viewport. Honours
  /// reduce-motion (instant jump) like every other animation here.
  void focusOn(String uuid) {
    final s = sim;
    final b = s?.body(uuid);
    if (s == null || b == null) return;
    if (_reducedMotion) {
      view.centerWorld(b.position, minScaleToFit: math.max(view.scale, 1.0));
      return;
    }
    _focusCtrl?.dispose();
    _focusFromTranslation = view.translation;
    _focusFromScale = view.scale;
    final targetScale = math.max(view.scale, 1.0);
    _focusToTranslation = Offset(
      view.viewport.width / 2 - b.position.dx * targetScale,
      view.viewport.height / 2 - b.position.dy * targetScale,
    );
    _focusToScale = targetScale;
    _focusCtrl = AnimationController(vsync: this, duration: _focusDuration)
      ..addListener(() {
        final t = DsMotion.enter.transform(_focusCtrl!.value);
        view.applyTransform(
          translation:
              Offset.lerp(_focusFromTranslation, _focusToTranslation, t) ??
              view.translation,
          scale: _focusFromScale! + (_focusToScale! - _focusFromScale!) * t,
        );
      })
      ..forward();
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(graphDataProvider);
    _ingest(async.value);
    final s = sim;
    final m = measurer;
    final p = palette;

    if (s != null && m != null && p != null && s.data.nodes.isNotEmpty) {
      return _canvasStack(context, s, m, p);
    }
    if (async.hasValue) {
      return const _EmptyCanvas();
    }
    return ColoredBox(
      color: context.dae.background,
      child: const Center(child: DsEyebrow('Graf')),
    );
  }

  Widget _canvasStack(
    BuildContext context,
    GraphSimulation s,
    GraphNodeMeasurer m,
    GraphPalette p,
  ) {
    final painter = GraphCanvasPainter(
      sim: s,
      view: view,
      palette: p,
      measurer: m,
      reveal: revealValue,
      revealActive: revealActive,
      selectedUuid: selectedUuid,
      structuralKey: _structuralKey,
      repaint: repaint,
    );
    final selectedNode = selectedUuid == null
        ? null
        : s.data.byUuid[selectedUuid];
    final isolatedCount = s.data.nodes
        .where((n) => s.data.isIsolated(n.uuid))
        .length;

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: painter),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _handleTap(d.globalPosition),
            onDoubleTapDown: (d) => _doubleTapAt = d.globalPosition,
            onDoubleTap: _handleDoubleTap,
            child: const SizedBox.expand(),
          ),
        ),
        _SemanticsLayer(state: this),
        if (selectedNode != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: DsEnter(
              travel: 18,
              duration: DsMotion.panel,
              child: _SelectionPanel(state: this, selected: selectedNode),
            ),
          )
        else if (isolatedCount > 0)
          Positioned(
            left: Ds.s4,
            bottom: Ds.s2,
            child: DsText.caption(
              '$isolatedCount item tak tertaut di tepi kanvas',
            ),
          ),
      ],
    );
  }
}

enum _TouchMode { none, pan, nodeDrag, pinch }

/// Invitation shown when the vault has no items at all — "unlinked" starts
/// at zero, and the product should say so.
class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas();

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return ColoredBox(
      color: dae.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DsText.section('Belum ada yang terhubung'),
            const SizedBox(height: Ds.s2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Ds.s6),
              child: DsText.body(
                'Buat catatan dan tugas, lalu tautkan — benang-benangnya '
                'inilah produknya.',
                align: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen-reader surface: one Semantics node per graph node, positioned in
/// sync with the layout but rebuilt only on structural change / settle, not
/// per tick. Selection state is carried in the label (`selected:` too, so
/// announced state follows the visual one).
class _SemanticsLayer extends StatelessWidget {
  const _SemanticsLayer({required this.state});

  final GraphCanvasState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state.structureVersion,
      builder: (context, _) {
        final s = state.sim;
        if (s == null || s.data.nodes.isEmpty) return const SizedBox.shrink();
        final children = <Widget>[];
        for (final n in s.data.nodes) {
          final b = s.body(n.uuid);
          if (b == null) continue;
          final topLeft = state.view.worldToScreen(
            b.position - Offset(b.size.width / 2, b.size.height / 2),
          );
          final degree = s.data.degreeOf(n.uuid);
          final kind = n.type == DaeItemType.note ? 'Catatan' : 'Tugas';
          final status = n.type == DaeItemType.todo
              ? (n.done ? ', selesai' : ', belum selesai')
              : '';
          final label =
              '$kind: ${n.title}$status, $degree tautan'
              '${degree == 0 ? ' — belum tertaut' : ''}'
              '${state.selectedUuid == n.uuid ? ', terpilih' : ''}';
          children.add(
            Positioned(
              left: topLeft.dx,
              top: topLeft.dy,
              width: math.max(1, b.size.width * state.view.scale),
              height: math.max(1, b.size.height * state.view.scale),
              child: Semantics(
                button: true,
                selected: state.selectedUuid == n.uuid,
                label: label,
                onTap: () => state.select(n.uuid),
                child: const SizedBox.expand(),
              ),
            ),
          );
        }
        return IgnorePointer(
          // ignoring hit tests, semantics stay in the tree (see
          // RenderIgnorePointer docs — ExcludeSemantics would remove them,
          // which is the opposite of what we want here).
          child: Stack(children: children),
        );
      },
    );
  }
}

/// The bichrome inspector for the selected node: its immediate neighbours,
/// each row wearing the same ThreadRail colour the list spine uses. This is
/// the "surface its neighbours" half of tap-to-select.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.state, required this.selected});

  final GraphCanvasState state;
  final GraphNode selected;

  static const int _visibleNeighbours = 8;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final s = state.sim!;
    final neighborUuids = s.data.neighborsOf(selected.uuid).toList()
      ..sort((a, b) {
        final na = s.data.byUuid[a]!.title.toLowerCase();
        final nb = s.data.byUuid[b]!.title.toLowerCase();
        return na.compareTo(nb);
      });
    final shown = neighborUuids.take(_visibleNeighbours).toList();
    final rest = neighborUuids.length - shown.length;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: dae.surface,
          border: Border(
            top: BorderSide(color: dae.hairline.withValues(alpha: 0.4)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s3, Ds.s3, Ds.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DsTypeMark(selected.type),
                const SizedBox(width: Ds.s2),
                Expanded(
                  child: DsText.bodyStrong(
                    selected.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DsButton.ghost(
                  label: 'Buka',
                  onPressed: () => state.widget.onOpenItem?.call(
                    selected.type,
                    selected.uuid,
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup pilihan',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => state.select(null),
                  icon: Icon(Icons.close, size: 18, color: dae.onSurface),
                ),
              ],
            ),
            const SizedBox(height: Ds.s1),
            DsEyebrow(
              neighborUuids.isEmpty
                  ? 'Belum tertaut — belum ada benang'
                  : '${neighborUuids.length} benang langsung',
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: Ds.s2),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        DsEnter(
                          key: ValueKey(shown[i]),
                          index: i,
                          travel: 8,
                          duration: DsMotion.panel,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: Ds.s2),
                            child: DsCard(
                              thread: Ds.threadColor(
                                selected.type,
                                s.data.byUuid[shown[i]]!.type,
                              ),
                              drawOn: true,
                              onTap: () => state.select(shown[i]),
                              padding: const EdgeInsets.symmetric(
                                horizontal: Ds.s3,
                                vertical: Ds.s2,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DsText.body(
                                      s.data.byUuid[shown[i]]!.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: Ds.s2),
                                  DsTypeMark(s.data.byUuid[shown[i]]!.type),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (rest > 0) DsText.caption('+ $rest benang lain'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
