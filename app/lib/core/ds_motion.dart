import 'package:flutter/material.dart';

import 'ds_theme.dart';

/// The app's motion vocabulary, in one place.
///
/// DaeNotes' chrome is ink-on-paper and quiet, so motion is deliberately
/// *calm*: entrances commit fast and land slowly ([DsMotion.enter]), exits
/// leave quickly ([DsMotion.exit]), and nothing bounces — the one
/// overshooting moment stays the thread draw, so it keeps meaning "a
/// connection appeared".
///
/// Every widget here degrades to **no movement** under reduce-motion, matching
/// `ThreadRail` and the graph reveal.
abstract final class DsMotion {
  // ------------------------------------------------------------------ curves
  /// Signature entrance. Leaves at ~70% of the distance in the first third of
  /// the time, then settles — the difference between "stiff" and "deliberate".
  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1);

  /// On-screen state change: smooth at both ends so nothing snaps.
  static const Curve onScreen = Cubic(0.2, 0.0, 0.0, 1);

  /// Exit: gentle start, quick departure. Never the entrance curve in reverse.
  static const Curve exit = Cubic(0.4, 0.0, 1, 1);

  /// Loops only — sine has no corner at either end, so a pulse never hitches.
  static const Curve ambient = Curves.easeInOutSine;

  // --------------------------------------------------------------- durations
  /// Finger-down response. Anything slower reads as lag.
  static const Duration press = Duration(milliseconds: 110);

  /// Lifting off: a touch longer than the press so the settle is visible.
  static const Duration release = Duration(milliseconds: 190);

  /// Tiny feedback (toggle glyph, colour).
  static const Duration micro = Duration(milliseconds: 150);

  /// Default for state changes and short moves.
  static const Duration standard = Duration(milliseconds: 240);

  /// Panels, sheets, selection surfaces.
  static const Duration panel = Duration(milliseconds: 320);

  /// Route enter (distance-scaled: a whole screen travels further than a row).
  static const Duration page = Duration(milliseconds: 420);
  static const Duration pageExit = Duration(milliseconds: 260);

  /// The 3px rail drawing itself down the spine.
  static const Duration railDraw = Duration(milliseconds: 420);

  /// Graph signature: threads drawn one after another on first mount.
  static const Duration canvasReveal = Duration(milliseconds: 1100);

  /// Centring a node on `focus=` — slow enough to read as a camera move.
  static const Duration focusPan = Duration(milliseconds: 460);

  // --------------------------------------------------------- choreography
  /// Micro-cascade step for list rows.
  static const Duration stagger = Duration(milliseconds: 34);

  /// Rows past this index share the last delay, keeping the whole entrance
  /// under half a second — a long list must not feel like a queue.
  static const int staggerLastRow = 8;

  static Duration staggerDelay(int index) =>
      stagger * (index > staggerLastRow ? staggerLastRow : index);
}

/// Rises (and fades) into place once, when it is first inserted.
///
/// Give list rows an [index] to get a staggered cascade for free: the delay is
/// folded into the animation curve instead of a timer, so nothing can leave a
/// pending `Timer` behind in tests.
class DsEnter extends StatelessWidget {
  const DsEnter({
    super.key,
    required this.child,
    this.index = 0,
    this.travel = 14,
    this.duration = DsMotion.standard,
    this.curve = DsMotion.enter,
  });

  final Widget child;
  final int index;

  /// Pixels travelled upward. Zero makes this a pure fade.
  final double travel;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    final delay = DsMotion.staggerDelay(index);
    final total = duration + delay;
    return TweenAnimationBuilder<double>(
      // Runs 0→1 exactly once when the element is created, then holds.
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      builder: (context, value, child) {
        final t = Interval(
          delay.inMilliseconds / total.inMilliseconds,
          1,
          curve: curve,
        ).transform(value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, travel * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Press feedback: the wrapped control shrinks a hair under the finger and
/// springs back on release.
///
/// Built on [Listener] so it never competes with the child's own gesture
/// detectors — an [InkWell] keeps its splash and semantics.
class DsPressable extends StatefulWidget {
  const DsPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressScale = 0.975,
  });

  final Widget child;
  final bool enabled;

  /// 2.5% is felt without looking like the control is being squeezed.
  final double pressScale;

  @override
  State<DsPressable> createState() => _DsPressableState();
}

class _DsPressableState extends State<DsPressable> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _down && widget.enabled && !context.reduceMotion;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setDown(true),
      onPointerUp: (_) => _setDown(false),
      onPointerCancel: (_) => _setDown(false),
      child: AnimatedScale(
        scale: pressed ? widget.pressScale : 1,
        duration: pressed ? DsMotion.press : DsMotion.release,
        curve: DsMotion.onScreen,
        child: widget.child,
      ),
    );
  }
}

/// The ambient layer: a slow, seamless breathe used only while something is
/// genuinely in progress (the sync dot). Static when [active] is false, and
/// never animates under reduce-motion.
class DsPulse extends StatefulWidget {
  const DsPulse({
    super.key,
    required this.child,
    this.active = true,
    this.period = const Duration(milliseconds: 900),
  });

  final Widget child;
  final bool active;
  final Duration period;

  @override
  State<DsPulse> createState() => _DsPulseState();
}

class _DsPulseState extends State<DsPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DsPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
    }
    _sync();
  }

  void _sync() {
    if (widget.active && !context.reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else if (_controller.isAnimating) {
      // Parked at 1 so a stopped pulse always looks "on", never half-faded.
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || context.reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = DsMotion.ambient.transform(_controller.value);
        return Opacity(
          opacity: 0.55 + 0.45 * t,
          child: Transform.scale(scale: 1 + 0.12 * t, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// Route transition: a short horizontal drift with a cross-fade, so pushing a
/// detail screen reads as "one item deeper", not a slide from the right.
///
/// The direction is deliberately *not* Material's default; it echoes the
/// ThreadRail entering from the left edge of every card.
///
/// Pass [secondaryAnimation] (the route *underneath*) to have that page settle
/// back and dim instead of freezing while the new page arrives.
class DsRouteTransition extends StatelessWidget {
  const DsRouteTransition({
    super.key,
    required this.animation,
    required this.child,
    this.secondaryAnimation,
    this.dx = -0.04,
    this.curve = DsMotion.enter,
    this.reverseCurve = DsMotion.exit,
  });

  final Animation<double> animation;
  final Widget child;
  final Animation<double>? secondaryAnimation;

  /// Travel as a fraction of the route's own width.
  final double dx;
  final Curve curve;
  final Curve reverseCurve;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: reverseCurve,
    );
    final Widget moved;
    if (context.reduceMotion) {
      // Keep the fade (it still explains where the surface came from) and drop
      // the displacement.
      moved = FadeTransition(opacity: curved, child: child);
    } else {
      moved = AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          final t = curved.value;
          return Opacity(
            opacity: t,
            child: FractionalTranslation(
              translation: Offset(dx * (1 - t), 0),
              child: child,
            ),
          );
        },
        child: child,
      );
    }
    final behind = secondaryAnimation;
    if (behind == null) return moved;
    // Outgoing page: 4% shrink and a 45% dim, ending before the incoming page
    // has landed so the two never look equally important.
    final settle = CurvedAnimation(
      parent: behind,
      curve: Interval(0, 0.75, curve: DsMotion.exit),
    );
    return AnimatedBuilder(
      animation: settle,
      builder: (context, child) {
        final t = settle.value;
        return Opacity(
          opacity: 1 - 0.45 * t,
          child: Transform.scale(scale: 1 - 0.04 * t, child: child),
        );
      },
      child: moved,
    );
  }
}
