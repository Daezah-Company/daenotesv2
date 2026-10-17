import 'package:flutter/material.dart';

import 'ds_motion.dart';
import 'ds_theme.dart';
import 'ds_tokens.dart';

/// The DaeNotes bottom sheet: ink-on-paper surface, square-ish top corners,
/// and the shared motion vocabulary instead of Material's default sheet curve.
///
/// Sheets arrive at `panel` speed on the entrance curve and leave faster on the
/// exit curve, like every other surface in the app. Callers that carry a text
/// field still wrap their own content in the keyboard inset.
Future<T?> showDsSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor ?? context.dae.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.radiusLg)),
    ),
    sheetAnimationStyle: AnimationStyle(
      duration: context.reduceMotion ? Duration.zero : DsMotion.panel,
      curve: DsMotion.enter,
      reverseDuration: context.reduceMotion ? Duration.zero : DsMotion.standard,
      reverseCurve: DsMotion.exit,
    ),
    builder: builder,
  );
}
