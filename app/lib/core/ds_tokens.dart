import 'package:flutter/painting.dart';

import 'dae_types.dart';

/// Design tokens for DaeNotes — strict monochrome: #282828 and white.
/// Secondary contrast and hairlines are alpha blends of those two values.
abstract final class Ds {
  // ---------------------------------------------------------------- chrome
  /// Dark surface, text colour above `paper`.
  static const Color ink = Color(0xFF282828);

  /// Compatibility alias. The canvas uses the same graphite as the chrome.
  static const Color inkDeep = ink;

  /// Compatibility alias. Hierarchy comes from spacing and hairlines.
  static const Color inkLift = ink;

  /// Light surface, text colour above `ink`. Paper is the one light surface;
  /// cards on it are separated by `ink` hairlines, not by a second white.
  static const Color paper = Color(0xFFFFFFFF);

  /// White at reduced opacity, for secondary text/hairlines on graphite.
  static const Color paperVeil = Color(0xB8FFFFFF);

  /// Secondary text on graphite, composited from white.
  static const Color veilOnInk = Color(0xB8FFFFFF);

  /// Secondary text on white, composited from graphite.
  static const Color veilOnPaper = Color(0xB8282828);

  // --------------------------------------------------------------- threads
  /// Monochrome relation/status roles. Their semantic names remain for API
  /// compatibility; widgets resolve them against the active theme surface.
  static const Color threadAmber = ink;

  /// note -> todo.
  static const Color threadMoss = ink;

  /// todo -> todo.
  static const Color threadSlate = ink;

  /// reminder / active status.
  static const Color threadRose = ink;

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
  static const double radiusSm = 2;
  static const double radius = 4;
  static const double radiusLg = 8;

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
