import 'dart:math' as math;

import 'package:daenotes/core/ds.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CONTRACT §6 pins the chrome to graphite/paper and reserves colour for
/// relations. These assertions exist because the implementation once drifted to
/// a green-tinted charcoal; the hexes below are the contract's, verbatim.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('monochrome palette (CONTRACT §6)', () {
    test('chrome uses only graphite and white', () {
      expect(Ds.ink, const Color(0xFF282828));
      expect(Ds.inkDeep, Ds.ink);
      expect(Ds.inkLift, Ds.ink);
      expect(Ds.paper, const Color(0xFFFFFFFF));
      expect(Ds.paperVeil, const Color(0xB8FFFFFF));
    });

    test('semantic marks and relation roles stay monochrome', () {
      for (final c in [
        Ds.threadAmber,
        Ds.threadMoss,
        Ds.threadSlate,
        Ds.threadRose,
      ]) {
        expect(c, Ds.ink);
      }
    });
  });

  group('text on the two surfaces', () {
    // Built per test: ThemeData touches google_fonts, which needs the test
    // binding already initialised.
    DaeTokens dark() => DsTheme.dark().extension<DaeTokens>()!;
    DaeTokens light() => DsTheme.light().extension<DaeTokens>()!;

    test('secondary text clears AA against its own background', () {
      // paperVeil alone is 3.4:1 on #FFFFFF, so each mode carries its own veil.
      expect(
        _contrast(dark().onSurfaceSecondary, dark().background),
        greaterThanOrEqualTo(4.5),
        reason: 'dark secondary text on #282828',
      );
      expect(
        _contrast(light().onSurfaceSecondary, light().background),
        greaterThanOrEqualTo(4.5),
        reason: 'light secondary text on #FFFFFF',
      );
    });

    test('primary text clears AA and threads stay legible on the canvas', () {
      expect(_contrast(dark().onSurface, dark().background), greaterThan(12));
      expect(_contrast(light().onSurface, light().background), greaterThan(12));
      expect(_contrast(dark().onSurface, dark().background), greaterThan(12));
    });
  });
}
