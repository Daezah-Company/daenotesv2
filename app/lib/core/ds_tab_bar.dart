import 'package:flutter/material.dart';

import 'ds_motion.dart';
import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

/// A compact Swiss-style navigation rail with a crisp sliding selection.
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Ds.s5, Ds.s2, Ds.s5, Ds.s2),
        child: SizedBox(
          height: 58,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / labels.length;
              final reduced = context.reduceMotion;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: dae.elevated,
                  borderRadius: BorderRadius.circular(Ds.radius),
                  border: Border.all(
                    color: dae.hairline.withValues(alpha: 0.12),
                  ),
                ),
                child: Stack(
                  children: [
                    if (reduced)
                      Positioned(
                        left: slot * currentIndex + 4,
                        top: 4,
                        bottom: 4,
                        width: slot - 8,
                        child: const _ActiveTabSurface(),
                      )
                    else
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: LayoutBuilder(
                            builder: (context, inner) =>
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: currentIndex.toDouble(),
                                    end: currentIndex.toDouble(),
                                  ),
                                  duration: DsMotion.panel,
                                  curve: DsMotion.enter,
                                  builder: (context, index, child) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Transform.translate(
                                      offset: Offset(slot * index, 0),
                                      child: SizedBox(
                                        width: slot - 8,
                                        height: inner.maxHeight,
                                        child: child,
                                      ),
                                    ),
                                  ),
                                  child: const _ActiveTabSurface(),
                                ),
                          ),
                        ),
                      ),
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
                              activeColor: dae.background,
                              inactiveColor: dae.onSurfaceSecondary,
                              onTap: () => onChanged(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActiveTabSurface extends StatelessWidget {
  const _ActiveTabSurface();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('activeTabSurface'),
    decoration: BoxDecoration(
      color: context.dae.onSurface,
      borderRadius: BorderRadius.circular(Ds.radiusSm),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: DsPressable(
        pressScale: 0.96,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.expand(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    AnimatedScale(
                      scale: active ? 1 : 0.92,
                      duration: context.reduceMotion
                          ? Duration.zero
                          : DsMotion.standard,
                      curve: DsMotion.enter,
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedDefaultTextStyle(
                        duration: context.reduceMotion
                            ? Duration.zero
                            : DsMotion.standard,
                        curve: DsMotion.onScreen,
                        style: DsType.eyebrow(
                          color: color,
                          weight: active ? FontWeight.w700 : FontWeight.w500,
                          size: 10,
                        ),
                        child: Text(label.toUpperCase(), maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
