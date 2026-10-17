import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// World <-> screen transform for the canvas: uniform scale plus translation
/// kept as plain values (not a raw matrix) so every update can be sanitised.
/// Pan + pinch write through this controller; the painter applies
/// [transformStorage] to the canvas. Extends ChangeNotifier purely as a
/// *repaint* signal — the widget never rebuilds on it.
class GraphViewController extends ChangeNotifier {
  static const double minScale = 0.25;
  static const double maxScale = 3.5;

  double _scale = 1;
  Offset _translation = Offset.zero;
  Size _viewport = Size.zero;

  double get scale => _scale;
  Offset get translation => _translation;
  Size get viewport => _viewport;

  void setViewport(Size size) {
    if (size == _viewport) return;
    _viewport = size;
  }

  /// Column-major 16 floats for `Canvas.transform`: scale then translate,
  /// built directly (screen = world * scale + translation).
  Float64List get transformStorage => Float64List.fromList(<double>[
    _scale, 0, 0, 0, //
    0, _scale, 0, 0, //
    0, 0, 1, 0, //
    _translation.dx, _translation.dy, 0, 1, //
  ]);

  Offset screenToWorld(Offset screen) {
    if (_scale <= 0) return Offset.zero;
    return (screen - _translation) / _scale;
  }

  Offset worldToScreen(Offset world) => world * _scale + _translation;

  void panBy(Offset deltaScreen) {
    if (!deltaScreen.isFinite) return;
    _translation += deltaScreen;
    notifyListeners();
  }

  /// Direct transform write (used by the focus animation). Sanitised so a
  /// bad tween value can never poison the matrix.
  void applyTransform({double? scale, Offset? translation}) {
    if (scale != null && scale.isFinite) {
      _scale = scale.clamp(minScale, maxScale);
    }
    if (translation != null && translation.isFinite) {
      _translation = translation;
    }
    notifyListeners();
  }

  /// Pinch/zoom keeping [focalScreen] fixed (the two-finger midpoint).
  void zoomBy(double factor, Offset focalScreen) {
    if (!factor.isFinite || factor <= 0 || !focalScreen.isFinite) return;
    final next = (_scale * factor).clamp(minScale, maxScale);
    final applied = next / _scale;
    _translation = focalScreen - (focalScreen - _translation) * applied;
    _scale = next;
    notifyListeners();
  }

  void setZoomAtCenter(double factor) =>
      zoomBy(factor, Offset(_viewport.width / 2, _viewport.height / 2));

  /// Centre a world point in the viewport, optionally at a minimum scale so
  /// deep-links (`focusOn`) always land readable.
  void centerWorld(Offset world, {double? minScaleToFit}) {
    if (!world.isFinite) return;
    if (minScaleToFit != null) {
      final next = math.max(_scale, minScaleToFit).clamp(minScale, maxScale);
      _scale = next;
    }
    _translation = Offset(
      _viewport.width / 2 - world.dx * _scale,
      _viewport.height / 2 - world.dy * _scale,
    );
    notifyListeners();
  }

  /// Fit the whole connected layout (plus the isolated ring) on screen with
  /// breathing room; used for the very first data arrival only.
  void fitContent(double contentRadius, Size size) {
    if (contentRadius <= 1 || !size.isFinite) return;
    final padding = 60.0;
    final fit =
        ((math.min(size.width, size.height) - padding * 2) /
                (contentRadius * 2))
            .clamp(minScale, 1.0);
    _scale = fit;
    _translation = Offset(size.width / 2, size.height / 2);
    notifyListeners();
  }

  /// World-space rect visible on screen, inflated for culling margins.
  Rect worldViewportRect({double margin = 160}) {
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(
      Offset(_viewport.width, _viewport.height),
    );
    return Rect.fromPoints(topLeft, bottomRight).deflate(-margin);
  }
}
