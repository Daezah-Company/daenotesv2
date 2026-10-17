import 'package:flutter/widgets.dart';

import 'ds_theme.dart';
import 'ds_tokens.dart';

/// The DaeNotes signature: the 3px left rail on every list-row spine.
/// It carries a thread colour when the item has connections and stays
/// empty (transparent, gutter preserved) when the item is isolated —
/// the visual incentive to link things.
///
/// When [drawOn] is true the rail animates in with the signature
/// "thread draw" (extends from the top over [Ds.motionThreadDraw]).
/// Honours reduce-motion: instant, no draw-on.
///
/// Use inside a `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` or
/// give the parent an explicit height; the rail fills its parent's height.
class ThreadRail extends StatelessWidget {
  const ThreadRail({
    super.key,
    this.thread,
    this.width = Ds.railWidth,
    this.drawOn = false,
  });

  /// The connection colour, or null when the item is isolated.
  /// Get it from `Ds.threadColor(...)` / `daeThreadBetween(...)`.
  final Color? thread;

  /// Defaults to the signature 3px.
  final double width;

  /// Animate the thread draw on first build (ignored under reduce-motion).
  final bool drawOn;

  @override
  Widget build(BuildContext context) {
    final color = thread;
    return SizedBox(
      width: width,
      child: color == null
          ? const ColoredBox(color: Color(0x00000000))
          : _ThreadLine(color: color, drawOn: drawOn && !context.reduceMotion),
    );
  }
}

class _ThreadLine extends StatelessWidget {
  const _ThreadLine({required this.color, required this.drawOn});

  final Color color;
  final bool drawOn;

  @override
  Widget build(BuildContext context) {
    if (!drawOn) return ColoredBox(color: color);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Ds.motionThreadDraw,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            // No room to draw progressively — show the full thread.
            return ColoredBox(color: color);
          }
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: constraints.maxHeight * t,
              child: ColoredBox(color: color),
            ),
          );
        },
      ),
    );
  }
}
