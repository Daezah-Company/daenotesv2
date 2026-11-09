import 'package:flutter/material.dart';

import 'ds_theme.dart';

/// Continues Android's white launch screen with the same square DaeNotes mark,
/// then fades away once the first app frame is ready.
class DaeSplashReveal extends StatefulWidget {
  const DaeSplashReveal({super.key, required this.child});

  final Widget child;

  @override
  State<DaeSplashReveal> createState() => _DaeSplashRevealState();
}

class _DaeSplashRevealState extends State<DaeSplashReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _showSplash = false);
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = _controller.value;
                final exit = Curves.easeInOut.transform(
                  ((t - .76) / .24).clamp(0.0, 1.0),
                );
                final opacity = 1 - exit;
                final reveal = Curves.easeOutCubic.transform(
                  (t / .54).clamp(0.0, 1.0),
                );
                final scale = 0.94 + 0.06 * reveal;
                final rise = 7 * (1 - reveal);

                return IgnorePointer(
                  child: Opacity(
                    opacity: opacity,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Center(
                        child: Transform.translate(
                          offset: Offset(0, rise),
                          child: Transform.scale(
                            scale: scale,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.center,
                                widthFactor: reveal,
                                child: Image.asset(
                                  'assets/branding/daenotes_icon_foreground.png',
                                  width: 168,
                                  height: 168,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  cacheWidth: 504,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
