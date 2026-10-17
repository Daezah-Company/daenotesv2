import 'package:flutter/material.dart';

import 'ds_theme.dart';
import 'ds_tokens.dart';
import 'ds_typography.dart';

/// Text pre-bound to the DaeNotes type scale. Pick the slot, not the style:
/// `DsText.section('Yesterday')`, `DsText.caption('3d')`. Colour is resolved
/// from `context.dae`, so dark/light just works.
class DsText extends StatelessWidget {
  const DsText._({
    super.key,
    required this.data,
    required this.role,
    this.maxLines,
    this.overflow,
    this.align,
    this.selectable = false,
  });

  /// Bricolage Grotesque 700 @ 34 — page-level display.
  factory DsText.display(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign? align,
    bool selectable = false,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.display,
    maxLines: maxLines,
    overflow: overflow,
    align: align,
    selectable: selectable,
  );

  /// Bricolage Grotesque 700 @ 28.
  factory DsText.displaySm(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.displaySm,
    maxLines: maxLines,
    overflow: overflow,
  );

  /// Bricolage Grotesque 600 @ 20 — section heading.
  factory DsText.section(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.section,
    maxLines: maxLines,
    overflow: overflow,
  );

  /// IBM Plex Sans 400 @ 15 — body/UI.
  factory DsText.body(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
    TextAlign? align,
    bool selectable = false,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.body,
    maxLines: maxLines,
    overflow: overflow,
    align: align,
    selectable: selectable,
  );

  /// IBM Plex Sans 600 @ 15 — emphasized UI text.
  factory DsText.bodyStrong(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.bodyStrong,
    maxLines: maxLines,
    overflow: overflow,
  );

  /// IBM Plex Mono 500 @ 12 — captions and counts (secondary colour).
  factory DsText.caption(
    String data, {
    Key? key,
    int? maxLines,
    TextOverflow? overflow,
  }) => DsText._(
    key: key,
    data: data,
    role: DsTextRole.caption,
    maxLines: maxLines,
    overflow: overflow,
  );

  /// Alias of caption for timestamps / relative time.
  factory DsText.timestamp(String data, {Key? key}) =>
      DsText._(key: key, data: data, role: DsTextRole.caption);

  final String data;
  final DsTextRole role;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? align;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final secondary = role == DsTextRole.caption;
    final style = switch (role) {
      DsTextRole.display => DsType.display(),
      DsTextRole.displaySm => DsType.display(size: Ds.displayM),
      DsTextRole.section => DsType.section(),
      DsTextRole.body => DsType.body(),
      DsTextRole.bodyStrong => DsType.body(weight: FontWeight.w600),
      DsTextRole.caption => DsType.caption(),
    };
    final textWidget = selectable
        ? SelectableText(
            data,
            style: style.copyWith(
              color: secondary ? dae.onSurfaceSecondary : dae.onSurface,
            ),
            maxLines: maxLines,
            textAlign: align,
          )
        : Text(
            data,
            style: style.copyWith(
              color: secondary ? dae.onSurfaceSecondary : dae.onSurface,
            ),
            maxLines: maxLines,
            overflow: overflow,
            textAlign: align,
          );
    return textWidget;
  }
}

enum DsTextRole { display, displaySm, section, body, bodyStrong, caption }
