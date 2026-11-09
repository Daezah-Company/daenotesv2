import 'package:flutter/widgets.dart';

import '../../core/ds.dart';
import 'graph_data.dart';

/// Lays out node labels once per (uuid, tone) and caches the [TextPainter]s
/// the painter reuses every frame. Node rects are sized from the measured
/// text — never a fixed guess.
///
/// Labels live in *world space* at a fixed font size; legibility at low zoom
/// is handled by fading labels out below a threshold rather than shrinking
/// them into mush.
class GraphNodeMeasurer {
  GraphNodeMeasurer({
    required this.textScale,
    required this.primaryColor,
    required this.secondaryColor,
  });

  /// Geometric type-mark slot inside the node's left edge.
  static const double markSlot = 20;
  static const double horizontalPadding = 20;
  static const double nodeHeight = 32;
  static const double minNodeWidth = 64;
  static const double maxNodeWidth = 200;
  static const double labelFontSize = 13;

  final double textScale;

  /// Monochrome label tones resolved once from the theme.
  final Color primaryColor;
  final Color secondaryColor;

  final Map<String, TextPainter> _cache = {};

  factory GraphNodeMeasurer.of(BuildContext context) {
    final dae = context.dae;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? const TextScaler.linear(1);
    final scaled = scaler.scale(1).clamp(0.9, 1.4);
    return GraphNodeMeasurer(
      textScale: scaled,
      primaryColor: dae.onSurface,
      secondaryColor: dae.onSurfaceSecondary,
    );
  }

  TextStyle _style(Color color) => DsType.body(
    color: color,
    weight: FontWeight.w500,
  ).copyWith(fontSize: labelFontSize * textScale, height: 1.2);

  /// Tone picks the cached variant: 0 = primary, 1 = secondary (isolated /
  /// done items read dimmer — status is a sanctioned place for hierarchy).
  TextPainter painterFor(GraphNode node, {int tone = 0}) {
    final key = '${node.uuid}:$tone';
    final cached = _cache[key];
    if (cached != null && cached.text!.toPlainText() == node.title) {
      return cached;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: node.title,
        style: _style(tone == 0 ? primaryColor : secondaryColor),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: (maxNodeWidth - markSlot - horizontalPadding));
    _cache[key] = tp;
    return tp;
  }

  /// Measured node size, clamped for extreme titles.
  Size sizeFor(GraphNode node) {
    final tp = painterFor(node);
    final w = (markSlot + tp.width + horizontalPadding).clamp(
      minNodeWidth,
      maxNodeWidth,
    );
    return Size(w, nodeHeight * textScale);
  }

  void clear() => _cache.clear();
}
