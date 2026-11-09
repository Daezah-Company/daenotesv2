import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ds_tokens.dart';

/// Resolved type styles for the three DaeNotes families.
/// Swiss typographic system: IBM Plex Sans for hierarchy and body, IBM Plex
/// Mono for compact utility data.
abstract final class DsType {
  static TextStyle display({
    double size = Ds.displayL,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.ibmPlexSans(
    fontSize: size,
    fontWeight: weight,
    height: 1.12,
    color: color,
  );

  /// Section heading — clear, compact grotesk hierarchy.
  static TextStyle section({Color? color}) => GoogleFonts.ibmPlexSans(
    fontSize: Ds.section,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: color,
  );

  static TextStyle body({Color? color, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.ibmPlexSans(
        fontSize: Ds.body,
        fontWeight: weight,
        height: 1.45,
        color: color,
      );

  /// Caption / timestamps / IDs — IBM Plex Mono 12px, weight 500.
  static TextStyle caption({
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: Ds.caption,
    fontWeight: weight,
    color: color,
  );

  /// Mono, uppercase, 0.06em tracking — eyebrows and tab labels.
  static TextStyle eyebrow({
    Color? color,
    FontWeight weight = FontWeight.w500,
    double size = Ds.caption,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: size * 0.06,
    color: color,
  );
}
