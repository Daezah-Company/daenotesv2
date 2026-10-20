import 'package:flutter/painting.dart';

import 'dae_types.dart';

/// Design tokens for DaeNotes — the single source of visual truth.
/// Concept (contract section 5): the chrome is strictly bichrome
/// graphite/paper; colour is reserved for connection threads, type marks and
/// status. Hexes here are contract section 6 verbatim — see
/// `test/theme/chrome_palette_test.dart`.
abstract final class Ds {
  // ---------------------------------------------------------------- chrome
  /// Dark surface, text colour above `paper`.
  static const Color ink = Color(0xFF282828);

  /// Deepest background (graph canvas).
  static const Color inkDeep = Color(0xFF1C1C1B);

  /// Elevated card / panel surface.
  static const Color inkLift = Color(0xFF353533);

  /// Light surface, text colour above `ink`. Paper is the one light surface;
  /// cards on it are separated by `ink` hairlines, not by a second white.
  static const Color paper = Color(0xFFFFFFFF);

  /// Secondary text / hairlines.
  static const Color paperVeil = Color(0xFF8B8B84);

  /// Secondary text on a dark surface. `paperVeil` alone is 4.47:1 on `ink`,
  /// just under AA, so the text role gets its own lift.
  static const Color veilOnInk = Color(0xFF9A9A93);

  /// Secondary text on `paper`. `paperVeil` on white is only 3.4:1.
  static const Color veilOnPaper = Color(0xFF6E6E68);

  // --------------------------------------------------------------- threads
  /// note -> note.
  static const Color threadAmber = Color(0xFFE3B23C);

  /// note -> todo.
  static const Color threadMoss = Color(0xFF6FA88A);

  /// todo -> todo.
  static const Color threadSlate = Color(0xFF7FA0C8);

  /// reminder / active status.
  static const Color threadRose = Color(0xFFC9768F);

  /// Thread colour for a connection between two item types.
  static Color threadColor(DaeItemType a, DaeItemType b) =>
      switch (daeThreadBetween(a, b)) {
        DaeThread.noteToNote => threadAmber,
        DaeThread.noteToTodo => threadMoss,
        DaeThread.todoToTodo => threadSlate,
        DaeThread.reminder => threadRose,
      };

  // -------------------------------------------------------------- spacing
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s8 = 48;

  // ---------------------------------------------------------------- radii
  static const double radiusSm = 10;
  static const double radius = 16;
  static const double radiusLg = 24;

  /// Signature 3px list-spine rail width.
  static const double railWidth = 3;

  // ------------------------------------------------------------- typography
  static const double displayL = 34;
  static const double displayM = 28;
  static const double section = 20;
  static const double body = 15;
  static const double caption = 12;

  /// Eyebrow letter-spacing, 0.06em at the caption size.
  static const double eyebrowSpacing = caption * 0.06;

  // ------------------------------------------------------------------ misc
  static const double hairline = 1;
  // Motion lives in `DsMotion` (ds_motion.dart) — one curve family, one
  // duration palette, so nothing moves on an ad-hoc timing.
}
