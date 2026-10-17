import 'package:flutter/material.dart';

import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

/// The DaeNotes tab strip: mono uppercase labels with an underline for the
/// active tab — per contract, a tab underline, not Material tabs.
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
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: _Tab(
                    label: labels[i],
                    icon: icons != null && i < icons!.length ? icons![i] : null,
                    active: i == currentIndex,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Ds.motionQuick,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? dae.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: 16, color: color),
            Text(
              label.toUpperCase(),
              style: DsType.eyebrow(
                color: color,
                weight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
