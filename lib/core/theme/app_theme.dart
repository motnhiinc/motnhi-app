import 'package:flutter/material.dart';

/// Design tokens from the Stitch "Storybook AR" / "Midnight Library" systems
/// (see docs/superpowers/specs/2026-08-24-storybook-ar-redesign-design.md).
///
/// A [ThemeExtension] so widgets read the full palette from the active theme
/// and Day -> Moon Mode cross-fades animate through [lerp].
@immutable
class StitchTokens extends ThemeExtension<StitchTokens> {
  const StitchTokens({
    required this.background,
    required this.canvas,
    required this.paper,
    required this.inputFill,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.coral,
    required this.coralPressed,
    required this.coralDeep,
    required this.lavender,
    required this.lavenderContainer,
    required this.sage,
    required this.sageContainer,
    required this.gold,
    required this.glass,
    required this.shadow,
  });

  /// App frame behind scrollable content.
  final Color background;

  /// Dimmer frame used behind centered cards (gate, dialogs).
  final Color canvas;

  /// Card surface ("thick paper").
  final Color paper;

  /// Text-entry fill.
  final Color inputFill;

  final Color ink;
  final Color inkMuted;
  final Color line;

  /// Primary action color (brightens in Moon Mode for contrast).
  final Color coral;
  final Color coralPressed;
  final Color coralDeep;

  final Color lavender;
  final Color lavenderContainer;
  final Color sage;
  final Color sageContainer;

  /// Reserved for magical moments only.
  final Color gold;

  /// Frosted nav-bar / sticky-bar fill.
  final Color glass;

  /// Warm ambient shadow color (never plain black).
  final Color shadow;

  static const day = StitchTokens(
    background: Color(0xFFFFF8F5),
    canvas: Color(0xFFF2EAE0),
    paper: Color(0xFFFFFAF4),
    inputFill: Color(0xFFFEF1EC),
    ink: Color(0xFF201A18),
    inkMuted: Color(0xFF746B66),
    line: Color(0xFFDBD0C4),
    coral: Color(0xFFDC704B),
    coralPressed: Color(0xFFB95639),
    coralDeep: Color(0xFF9B3F1E),
    lavender: Color(0xFF63539E),
    lavenderContainer: Color(0xFFBFADFF),
    sage: Color(0xFF3B644C),
    sageContainer: Color(0xFFBFEDCD),
    gold: Color(0xFFF2D493),
    glass: Color(0xF2FFFAF4),
    shadow: Color(0x264C392B),
  );

  static const moon = StitchTokens(
    background: Color(0xFF27223E),
    canvas: Color(0xFF140F2A),
    paper: Color(0xFF332C4C),
    inputFill: Color(0xFF211C37),
    ink: Color(0xFFF5F5F7),
    inkMuted: Color(0xFFC9C2E0),
    line: Color(0xFF5A527A),
    coral: Color(0xFFE38A6A),
    coralPressed: Color(0xFF8A3C22),
    coralDeep: Color(0xFFDE724D),
    lavender: Color(0xFFCCBEFF),
    lavenderContainer: Color(0xFF4D3D87),
    sage: Color(0xFFA4D1B3),
    sageContainer: Color(0xFF365A42),
    gold: Color(0xFFF2D493),
    glass: Color(0xE627223E),
    shadow: Color(0x59000000),
  );

  @override
  StitchTokens copyWith({
    Color? background,
    Color? canvas,
    Color? paper,
    Color? inputFill,
    Color? ink,
    Color? inkMuted,
    Color? line,
    Color? coral,
    Color? coralPressed,
    Color? coralDeep,
    Color? lavender,
    Color? lavenderContainer,
    Color? sage,
    Color? sageContainer,
    Color? gold,
    Color? glass,
    Color? shadow,
  }) {
    return StitchTokens(
      background: background ?? this.background,
      canvas: canvas ?? this.canvas,
      paper: paper ?? this.paper,
      inputFill: inputFill ?? this.inputFill,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      coral: coral ?? this.coral,
      coralPressed: coralPressed ?? this.coralPressed,
      coralDeep: coralDeep ?? this.coralDeep,
      lavender: lavender ?? this.lavender,
      lavenderContainer: lavenderContainer ?? this.lavenderContainer,
      sage: sage ?? this.sage,
      sageContainer: sageContainer ?? this.sageContainer,
      gold: gold ?? this.gold,
      glass: glass ?? this.glass,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  StitchTokens lerp(StitchTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return StitchTokens(
      background: c(background, other.background),
      canvas: c(canvas, other.canvas),
      paper: c(paper, other.paper),
      inputFill: c(inputFill, other.inputFill),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      line: c(line, other.line),
      coral: c(coral, other.coral),
      coralPressed: c(coralPressed, other.coralPressed),
      coralDeep: c(coralDeep, other.coralDeep),
      lavender: c(lavender, other.lavender),
      lavenderContainer: c(lavenderContainer, other.lavenderContainer),
      sage: c(sage, other.sage),
      sageContainer: c(sageContainer, other.sageContainer),
      gold: c(gold, other.gold),
      glass: c(glass, other.glass),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// Convenience access: `context.stitch.coral`.
extension StitchContextX on BuildContext {
  StitchTokens get stitch => Theme.of(this).extension<StitchTokens>()!;
}

/// Child-friendly theming (§26.1): warm colors, tactile depth, calm by
/// default. Two variants — bright "day" and the low-strain "Moon Mode"
/// bedtime theme (§7.1.6).
abstract final class AppTheme {
  static const serifFamily = 'SourceSerif4';
  static const sansFamily = 'NunitoSans';

  // Retained legacy metrics (still referenced by shared controls).
  static const double bigButtonSize = 72;
  static const double touchTargetMin = 44;
  static const double cardRadius = 22;

  static ThemeData day() => _build(StitchTokens.day, Brightness.light);
  static ThemeData bedtime() => _build(StitchTokens.moon, Brightness.dark);

  static ThemeData _build(StitchTokens t, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: t.coralDeep,
      brightness: brightness,
    ).copyWith(
      primary: t.coral,
      onPrimary: Colors.white,
      secondary: t.lavender,
      onSecondary: Colors.white,
      tertiary: t.sage,
      surface: t.paper,
      onSurface: t.ink,
      onSurfaceVariant: t.inkMuted,
      outline: t.line,
      outlineVariant: t.line,
      error: const Color(0xFFBA1A1A),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
    );

    final text = base.textTheme.apply(
          bodyColor: t.ink,
          displayColor: t.ink,
          fontFamily: sansFamily,
        ).copyWith(
          displayLarge: _serif(57, FontWeight.w600, t.ink),
          displayMedium: _serif(45, FontWeight.w600, t.ink),
          displaySmall: _serif(36, FontWeight.w600, t.ink),
          headlineLarge: _serif(32, FontWeight.w600, t.ink),
          headlineMedium: _serif(28, FontWeight.w600, t.ink, height: 1.2),
          headlineSmall: _serif(20, FontWeight.w600, t.ink, height: 1.3),
          titleLarge: _serif(22, FontWeight.w600, t.ink),
          titleMedium: _serif(17, FontWeight.w600, t.ink, height: 1.3),
          titleSmall: TextStyle(
            fontFamily: sansFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: t.ink,
          ),
          bodyLarge: TextStyle(
            fontFamily: sansFamily,
            fontSize: 16,
            height: 1.55,
            color: t.ink,
          ),
          bodyMedium: TextStyle(
            fontFamily: sansFamily,
            fontSize: 14,
            height: 1.55,
            color: t.ink,
          ),
          bodySmall: TextStyle(
            fontFamily: sansFamily,
            fontSize: 12.5,
            height: 1.45,
            color: t.inkMuted,
          ),
          labelLarge: TextStyle(
            fontFamily: sansFamily,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
          labelMedium: TextStyle(
            fontFamily: sansFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
          labelSmall: TextStyle(
            fontFamily: sansFamily,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.08,
            color: t.inkMuted,
          ),
        );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: t.line),
    );

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      extensions: [t],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: t.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: serifFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: t.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.paper,
        elevation: 6,
        shadowColor: t.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        titleTextStyle: TextStyle(
          fontFamily: serifFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: t.ink,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.ink,
        contentTextStyle: TextStyle(
          fontFamily: sansFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: t.background,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(touchTargetMin, 52),
          backgroundColor: t.coral,
          foregroundColor: Colors.white,
          textStyle: TextStyle(
            fontFamily: sansFamily,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(touchTargetMin, 52),
          foregroundColor: t.ink,
          side: BorderSide(color: t.line),
          textStyle: TextStyle(
            fontFamily: sansFamily,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: t.coral, width: 1.6),
        ),
        hintStyle: TextStyle(fontFamily: sansFamily, color: t.inkMuted),
        labelStyle: TextStyle(
          fontFamily: sansFamily,
          fontWeight: FontWeight.w700,
          color: t.ink,
        ),
      ),
      dividerTheme: DividerThemeData(color: t.line, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? t.sageContainer
              : t.line,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? t.coral
              : Colors.transparent,
        ),
        side: BorderSide(color: t.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );
  }

  static TextStyle _serif(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
  }) =>
      TextStyle(
        fontFamily: serifFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
      );
}
