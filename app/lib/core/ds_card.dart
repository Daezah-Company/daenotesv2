import 'package:flutter/material.dart';

import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'thread_rail.dart';

/// Bichrome panel with the signature [ThreadRail] fused to its left edge.
/// `thread == null` keeps the 3px rail empty — an isolated item.
/// Chrome never carries colour; only the rail does.
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.thread,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Ds.s4,
      vertical: Ds.s3,
    ),
    this.drawOn = false,
    this.selected = false,
  });

  final Widget child;
  final Color? thread;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Play the thread-draw on the rail when this card appears.
  final bool drawOn;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? Ds.inkLift : dae.elevated,
        borderRadius: BorderRadius.circular(Ds.radius),
        border: selected
            ? Border.all(color: dae.onSurface, width: 1.5)
            : Border.all(
                color: dae.hairline.withValues(alpha: 0.28),
                width: Ds.hairline,
              ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Ds.radius),
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ThreadRail(thread: thread, drawOn: drawOn),
                Expanded(
                  child: Padding(padding: padding, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
