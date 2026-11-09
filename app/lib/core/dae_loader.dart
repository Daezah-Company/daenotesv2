import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ds_theme.dart';

/// A quiet, lightweight DaeNotes progress mark: a single ink arc that turns
/// smoothly, without introducing a third brand color or a busy illustration.
class DaeLoader extends StatefulWidget {
  const DaeLoader({
    super.key,
    this.size = 18,
    this.color,
    this.strokeWidth = 1.6,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  State<DaeLoader> createState() => _DaeLoaderState();
}

class _DaeLoaderState extends State<DaeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 880),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (context.reduceMotion) {
      _controller.stop();
      _controller.value = 0.18;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.dae.onSurface;
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _DaeLoaderPainter(
              progress: _controller.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _DaeLoaderPainter extends CustomPainter {
  const _DaeLoaderPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.shortestSide - strokeWidth) / 2;
    final bounds = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      bounds,
      -math.pi / 2 + progress * math.pi * 2,
      math.pi * 1.34,
      false,
      ink,
    );
  }

  @override
  bool shouldRepaint(_DaeLoaderPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
