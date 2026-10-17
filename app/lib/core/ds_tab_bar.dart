import 'package:flutter/material.dart';

import 'ds_motion.dart';
import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

/// The DaeNotes tab strip: mono uppercase labels with an underline for the
/// active tab — per contract, a tab underline, not Material tabs.
///
/// The underline is one bar that *slides* to the chosen tab (rather than
/// fading in and out per tab), so switching tabs keeps spatial continuity.
class DsTabBar extends StatelessWidget {
  const DsTabBar({
    super.key,
    required this.labels,
    required this.currentIndex,
    required this.onChanged,
    this.icons,
  });

  final List<String> labels;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// Optional leading icon per tab (same index as [labels]).
  final List<IconData?>? icons;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dae.background,
        border: Border(
          top: BorderSide(color: dae.hairline.withValues(alpha: 0.28)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / labels.length;
              final reduced = context.reduceMotion;
              return Stack(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: _Tab(
                            label: labels[i],
                            icon: icons != null && i < icons!.length
                                ? icons![i]
                                : null,
                            active: i == currentIndex,
                            onTap: () => onChanged(i),
                          ),
                        ),
                    ],
                  ),
                  if (!reduced)
                    AnimatedPositioned(
                      duration: DsMotion.panel,
                      curve: DsMotion.enter,
                      left: slot * currentIndex,
                      bottom: 0,
                      width: slot,
                      child: const _TabUnderline(),
                    )
                  else
                    Positioned(
                      left: slot * currentIndex,
                      bottom: 0,
                      width: slot,
                      child: const _TabUnderline(),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The travelling bar: inset so it reads as an accent under the label, not a
/// full-width divider.
class _TabUnderline extends StatelessWidget {
  const _TabUnderline();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Ds.s4),
      child: SizedBox(
        height: 2,
        child: ColoredBox(color: context.dae.onSurface),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final color = active ? dae.onSurface : dae.onSurfaceSecondary;
    return DsPressable(
      pressScale: 0.94,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: 16, color: color),
            AnimatedDefaultTextStyle(
              duration: DsMotion.standard,
              curve: DsMotion.onScreen,
              style: DsType.eyebrow(
                color: color,
                weight: active ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label.toUpperCase()),
            ),
          ],
        ),
      ),
    );
  }
}
