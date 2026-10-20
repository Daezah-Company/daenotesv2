import 'package:flutter/material.dart';

import 'ds_tokens.dart';
import 'ds_typography.dart';

/// Semantic chrome roles derived from the bichrome tokens. Dark is the
/// product default; light swaps the same tokens (contract section 5).
@immutable
class DaeTokens extends ThemeExtension<DaeTokens> {
  const DaeTokens({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.onSurface,
    required this.onSurfaceSecondary,
    required this.hairline,
    required this.onAccent,
  });

  final bool isDark;

  /// Deepest canvas: inkDeep in dark, paper in light.
  final Color background;

  /// Normal chrome surface: ink in dark, paper in light.
  final Color surface;

  /// Raised card: inkLift in dark, paper in light.
  final Color elevated;

  /// Primary text: paper in dark, ink in light.
  final Color onSurface;

  /// Secondary text: the veil tuned for whichever surface it sits on, because
  /// one grey cannot clear AA on both #282828 and #FFFFFF.
  final Color onSurfaceSecondary;

  /// Hairline tint. Every consumer multiplies it by an alpha of 0.12–0.4, so
  /// light mode must tint with `ink` (a grey hairline on white disappears).
  final Color hairline;

  /// Text drawn on top of a coloured thread/status accent.
  final Color onAccent;

  static const DaeTokens dark = DaeTokens(
    isDark: true,
    background: Ds.inkDeep,
    surface: Ds.ink,
    elevated: Ds.inkLift,
    onSurface: Ds.paper,
    onSurfaceSecondary: Ds.veilOnInk,
    hairline: Ds.paperVeil,
    onAccent: Ds.ink,
  );

  static const DaeTokens light = DaeTokens(
    isDark: false,
    background: Ds.paper,
    surface: Ds.paper,
    elevated: Ds.paper,
    onSurface: Ds.ink,
    onSurfaceSecondary: Ds.veilOnPaper,
    hairline: Ds.ink,
    onAccent: Ds.paper,
  );

  @override
  DaeTokens copyWith({
    bool? isDark,
    Color? background,
    Color? surface,
    Color? elevated,
    Color? onSurface,
    Color? onSurfaceSecondary,
    Color? hairline,
    Color? onAccent,
  }) => DaeTokens(
    isDark: isDark ?? this.isDark,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    elevated: elevated ?? this.elevated,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceSecondary: onSurfaceSecondary ?? this.onSurfaceSecondary,
    hairline: hairline ?? this.hairline,
    onAccent: onAccent ?? this.onAccent,
  );

  @override
  DaeTokens lerp(covariant DaeTokens? other, double t) => other ?? this;
}

/// ThemeData built strictly from [Ds] tokens (contract section 6: no ad-hoc
/// ThemeData in widgets). Dark-first.
abstract final class DsTheme {
  static ThemeData dark() => _build(DaeTokens.dark);

  static ThemeData light() => _build(DaeTokens.light);

  static ThemeData _build(DaeTokens t) {
    final colorScheme = ColorScheme(
      brightness: t.isDark ? Brightness.dark : Brightness.light,
      primary: t.onSurface,
      onPrimary: t.background,
      secondary: Ds.threadSlate,
      onSecondary: Ds.ink,
      error: Ds.threadRose,
      onError: Ds.paper,
      surface: t.surface,
      onSurface: t.onSurface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: TextTheme(
        displayLarge: DsType.display(color: t.onSurface),
        displayMedium: DsType.display(size: Ds.displayM, color: t.onSurface),
        headlineSmall: DsType.section(color: t.onSurface),
        bodyLarge: DsType.body(color: t.onSurface),
        bodyMedium: DsType.body(color: t.onSurface),
        bodySmall: DsType.caption(color: t.onSurfaceSecondary),
        labelLarge: DsType.eyebrow(color: t.onSurface),
      ),
      cardTheme: CardThemeData(
        color: t.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Ds.radius),
          side: BorderSide(
            color: t.hairline.withValues(alpha: 0.28),
            width: Ds.hairline,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: t.hairline.withValues(alpha: 0.28),
        thickness: Ds.hairline,
        space: Ds.hairline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.background,
        foregroundColor: t.onSurface,
        elevation: 0,
        centerTitle: false,
        titleSpacing: Ds.s4,
      ),
      iconTheme: IconThemeData(color: t.onSurfaceSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.elevated,
        hintStyle: DsType.caption(color: t.onSurfaceSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Ds.s3,
          vertical: Ds.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.radiusSm),
          borderSide: BorderSide(color: t.hairline.withValues(alpha: 0.28)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.radiusSm),
          borderSide: BorderSide(color: t.hairline.withValues(alpha: 0.28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Ds.radiusSm),
          borderSide: BorderSide(color: t.onSurface, width: 1.5),
        ),
      ),
      extensions: [t],
    );
  }
}

/// Ergonomic accessors: `context.dae.onSurface`, `context.reduceMotion`.
extension DaeContext on BuildContext {
  DaeTokens get dae => Theme.of(this).extension<DaeTokens>() ?? DaeTokens.dark;

  /// True when the user asked the OS to reduce motion — thread draw and
  /// other choreography must collapse to instant display.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
