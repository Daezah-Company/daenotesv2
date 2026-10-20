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
  group('chrome palette (CONTRACT §6)', () {
    test('neutral chrome matches the contract hexes', () {
      expect(Ds.ink, const Color(0xFF282828));
      expect(Ds.inkDeep, const Color(0xFF1C1C1B));
      expect(Ds.inkLift, const Color(0xFF353533));
      expect(Ds.paper, const Color(0xFFFFFFFF));
      expect(Ds.paperVeil, const Color(0xFF8B8B84));
    });

    test('no green tint survives in the chrome tokens', () {
      for (final c in [
        Ds.ink,
        Ds.inkDeep,
        Ds.inkLift,
        Ds.paper,
        Ds.paperVeil,
      ]) {
        // Green-dominant was the drift; a warm-neutral grey is fine.
        expect(
          c.g,
          lessThanOrEqualTo(math.max(c.r, c.b) + 0.004),
          reason: '$c is green-dominant — chrome stays graphite/paper',
        );
      }
    });

    test('connection threads keep their colours — colour is relation', () {
      expect(Ds.threadAmber, const Color(0xFFE3B23C));
      expect(Ds.threadMoss, const Color(0xFF6FA88A));
      expect(Ds.threadSlate, const Color(0xFF7FA0C8));
      expect(Ds.threadRose, const Color(0xFFC9768F));
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
      for (final thread in [
        Ds.threadAmber,
        Ds.threadMoss,
        Ds.threadSlate,
        Ds.threadRose,
      ]) {
        expect(_contrast(thread, dark().background), greaterThanOrEqualTo(3));
      }
    });
  });
}
