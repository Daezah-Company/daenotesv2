import 'package:flutter/material.dart';

import 'ds_theme.dart';
import 'ds_motion.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

enum DsButtonVariant {
  /// Solid paper-on-ink (dark) action.
  filled,

  /// Hairline outline, transparent fill.
  outlined,

  /// No chrome until pressed.
  ghost,

  /// Destructive — the one place `threadRose` may dress a control (status).
  destructive,
}

/// Bichrome button. Label is mono uppercase (eyebrow voice). The only colour
/// allowed is the rose on `destructive`, which reads as a status.
class DsButton extends StatelessWidget {
  const DsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = DsButtonVariant.outlined,
    this.icon,
    this.expanded = false,
  });

  /// Compact primary action.
  const DsButton.filled({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  }) : variant = DsButtonVariant.filled;

  const DsButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  }) : variant = DsButtonVariant.ghost;

  const DsButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
  }) : variant = DsButtonVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final DsButtonVariant variant;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final enabled = onPressed != null;

    final (Color fg, Color bg, Color borderColor) = switch (variant) {
      DsButtonVariant.filled => (dae.background, dae.onSurface, dae.onSurface),
      DsButtonVariant.outlined => (
        dae.onSurface,
        Colors.transparent,
        dae.hairline.withValues(alpha: 0.4),
      ),
      DsButtonVariant.ghost => (
        dae.onSurfaceSecondary,
        Colors.transparent,
        Colors.transparent,
      ),
      DsButtonVariant.destructive => (
        Ds.threadRose,
        Colors.transparent,
        Ds.threadRose.withValues(alpha: 0.5),
      ),
    };

    final labelStyle = DsType.eyebrow(
      color: enabled ? fg : fg.withValues(alpha: 0.38),
      weight: FontWeight.w600,
    );

    final content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: labelStyle.color),
          const SizedBox(width: Ds.s2),
        ],
        Text(label.toUpperCase(), style: labelStyle),
      ],
    );

    return DsPressable(
      enabled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Ds.radiusSm),
            border: borderColor.a == 0 ? null : Border.all(color: borderColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(Ds.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Ds.s4),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
