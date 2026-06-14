import 'package:flutter/material.dart';

/// Child-friendly theming (§26.1): warm colors, big touch targets, calm by
/// default. Two variants — a bright "day" theme and a dimmer "bedtime" theme
/// (§7.1.6) used when bedtime mode is active.
abstract final class AppTheme {
  // Warm day palette.
  static const _dayPrimary = Color(0xFFEF7E54); // warm coral
  static const _daySecondary = Color(0xFF8B6FD6); // soft violet
  static const _dayBackground = Color(0xFFFFF6EC); // warm cream
  static const _daySurface = Color(0xFFFFFFFF);

  // Calm bedtime palette — deep, low-contrast, warm accents.
  static const _nightPrimary = Color(0xFFE9B872); // muted amber
  static const _nightSecondary = Color(0xFF8E86C9);
  static const _nightBackground = Color(0xFF161427); // deep indigo
  static const _nightSurface = Color(0xFF211E36);

  /// Large, rounded, high-affordance controls suit small hands (§4.2, §26.1).
  static const double bigButtonSize = 96;
  static const double touchTargetMin = 64;
  static const double cardRadius = 24;

  static ThemeData day() => _build(
        brightness: Brightness.light,
        primary: _dayPrimary,
        secondary: _daySecondary,
        background: _dayBackground,
        surface: _daySurface,
        onBackground: const Color(0xFF3A2E28),
      );

  static ThemeData bedtime() => _build(
        brightness: Brightness.dark,
        primary: _nightPrimary,
        secondary: _nightSecondary,
        background: _nightBackground,
        surface: _nightSurface,
        onBackground: const Color(0xFFE8E4F0),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    required Color onBackground,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      surface: surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: onBackground,
        displayColor: onBackground,
        fontFamilyFallback: const ['Comic Sans MS', 'Baloo 2'],
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(touchTargetMin, touchTargetMin),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onBackground,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
