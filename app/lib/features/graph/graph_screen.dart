import 'package:flutter/material.dart';

import '../../core/ds.dart';
import 'graph_canvas.dart';

/// The app's signature screen: the live link graph, offline-first.
///
/// Router wiring (integration agent):
///
/// ```dart
/// GraphScreen(
///   onOpenItem: (type, uuid) => context.push(
///     type == DaeItemType.note
///         ? DaeRouteNames.notePath(uuid)
///         : DaeRouteNames.todoPath(uuid),
///   ),
///   focusUuid: state.uri.queryParameters['focus'], // /graph?focus=<uuid>
/// )
/// ```
class GraphScreen extends StatelessWidget {
  const GraphScreen({super.key, this.onOpenItem, this.focusUuid});

  /// Invoked when the user double-taps a node. The router owner maps
  /// `(type, uuid)` to `noteDetail` / `todoDetail`.
  final GraphItemOpenCallback? onOpenItem;

  /// Deep-linked node uuid — the canvas centres it once the layout is live.
  final String? focusUuid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.dae.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GraphCanvas(onOpenItem: onOpenItem, focusUuid: focusUuid),
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Ds.s5, Ds.s4, Ds.s5, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DsText.displaySm('Peta ide'),
                      const SizedBox(height: Ds.s1),
                      DsText.caption(
                        'Geser untuk menjelajah · ketuk dua kali untuk membuka',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
