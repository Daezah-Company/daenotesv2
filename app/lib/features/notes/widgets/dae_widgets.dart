import 'package:flutter/material.dart';

import '../../../core/ds.dart';
import '../../../data/model/enums.dart';

/// A bichrome segmented control — the DS answer to Material chips/segmented
/// buttons. Chrome stays ink/paper; only the selected tab is marked.
class DsFilterControl extends StatelessWidget {
  const DsFilterControl({
    super.key,
    required this.options,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: EdgeInsets.only(right: Ds.s4),
            child: _Segment(
              label: options[i],
              active: i == currentIndex,
              onTap: () => onChanged(i),
              activeColor: dae.onSurface,
              idleColor: dae.onSurfaceSecondary,
            ),
          ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
    required this.activeColor,
    required this.idleColor,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final Color idleColor;

  @override
  Widget build(BuildContext context) {
    return DsPressable(
      pressScale: 0.94,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedDefaultTextStyle(
                duration: DsMotion.standard,
                curve: DsMotion.onScreen,
                style: DsType.eyebrow(
                  color: active ? activeColor : idleColor,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label.toUpperCase()),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: DsMotion.standard,
                curve: DsMotion.onScreen,
                height: 2,
                color: active ? activeColor : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Todo completion mark. A custom circle + check (not a Material Checkbox) so
/// it stays bichrome; `done` reads as filled status.
class DsCheckToggle extends StatelessWidget {
  const DsCheckToggle({
    super.key,
    required this.done,
    this.onTap,
    this.size = 22,
  });

  final bool done;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final reduced = context.reduceMotion;
    return DsPressable(
      enabled: onTap != null,
      pressScale: 0.88,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: DsMotion.micro,
                curve: DsMotion.onScreen,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? dae.onSurface : Colors.transparent,
                  border: Border.all(
                    color: done ? dae.onSurface : dae.onSurfaceSecondary,
                    width: 1.5,
                  ),
                ),
              ),
              // The check arrives a beat after the fill, so completing a todo
              // reads as two events (confirm, then mark) instead of a swap.
              AnimatedOpacity(
                opacity: done ? 1 : 0,
                duration: DsMotion.release,
                curve: DsMotion.enter,
                child: AnimatedScale(
                  scale: done ? 1 : 0.55,
                  duration: reduced
                      ? Duration.zero
                      : DsMotion.standard, // spatial — off under reduce-motion
                  curve: DsMotion.enter,
                  child: Icon(
                    Icons.check,
                    size: size * 0.7,
                    color: dae.onAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Priority selection as three bichrome options; the marked one is a status.
class DsPriorityPicker extends StatelessWidget {
  const DsPriorityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TodoPriority value;
  final ValueChanged<TodoPriority> onChanged;

  static const _labels = {
    TodoPriority.low: 'Rendah',
    TodoPriority.normal: 'Sedang',
    TodoPriority.high: 'Tinggi',
  };

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Row(
      children: [
        for (final p in TodoPriority.values)
          Padding(
            padding: EdgeInsets.only(right: Ds.s2),
            child: DsPressable(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: DsMotion.standard,
                  curve: DsMotion.onScreen,
                  decoration: BoxDecoration(
                    color: p == value ? dae.onSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(Ds.radiusSm),
                    border: Border.all(
                      color: p == value
                          ? dae.onSurface
                          : dae.hairline.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Ds.s3,
                      vertical: Ds.s2,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: DsMotion.standard,
                      curve: DsMotion.onScreen,
                      style: DsType.eyebrow(
                        color: p == value
                            ? dae.onAccent
                            : dae.onSurfaceSecondary,
                        weight: FontWeight.w600,
                      ),
                      child: Text((_labels[p] ?? p.wire).toUpperCase()),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A labelled field block: mono eyebrow above its content. Keeps form chrome
/// identical across note and todo editors.
class DsField extends StatelessWidget {
  const DsField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DsEyebrow(label),
        const SizedBox(height: Ds.s2),
        child,
      ],
    );
  }
}

/// Section heading with an inline trailing action slot.
class DsSectionHeader extends StatelessWidget {
  const DsSectionHeader({
    super.key,
    required this.text,
    this.accent,
    this.trailing,
  });

  final String text;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: DsEyebrow(text, accent: accent)),
        ?trailing,
      ],
    );
  }
}

/// Empty / error states written as invitations (contract §5 writing rules:
/// Indonesian, no apology, no vagueness). Colour-free chrome.
class DsInvitation extends StatelessWidget {
  const DsInvitation({
    super.key,
    required this.eyebrow,
    required this.headline,
    required this.hint,
    this.action,
  });

  final String eyebrow;
  final String headline;
  final String hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Ds.s5, vertical: Ds.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsEyebrow(eyebrow),
          const SizedBox(height: Ds.s3),
          DsText.section(headline),
          const SizedBox(height: Ds.s2),
          Text(hint, style: DsType.body(color: dae.onSurfaceSecondary)),
          if (action != null) ...[const SizedBox(height: Ds.s4), action!],
        ],
      ),
    );
  }
}
