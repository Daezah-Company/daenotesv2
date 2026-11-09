import 'package:flutter/widgets.dart';

import 'dae_types.dart';
import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

/// Mono uppercase tracked label used for eyebrows: the wordmark row, section
/// kickers, field labels. Uses the monochrome type scale by default; [accent]
/// remains for compatibility but app screens use only ink/paper roles.
class DsEyebrow extends StatelessWidget {
  const DsEyebrow(this.text, {super.key, this.accent, this.size = Ds.caption});

  final String text;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Text(
      text.toUpperCase(),
      style: DsType.eyebrow(
        size: size,
        color: accent ?? dae.onSurfaceSecondary,
      ),
    );
  }
}

/// Small NOTE / TODO marker, rendered with monochrome contrast.
class DsTypeMark extends StatelessWidget {
  const DsTypeMark(this.type, {super.key, this.filled = false});

  final DaeItemType type;

  /// Solid chip vs outline chip.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final color = dae.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? color : null,
        border: filled ? null : Border.all(color: color),
        borderRadius: BorderRadius.circular(Ds.radiusSm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          type.wire.toUpperCase(),
          style: DsType.eyebrow(
            size: 10,
            color: filled ? dae.onAccent : color,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
