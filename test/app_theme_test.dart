import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storybook_ar/core/theme/app_theme.dart';

void main() {
  void expectSerifStylesUseInk(ThemeData theme) {
    final ink = theme.extension<StitchTokens>()!.ink;
    final textTheme = theme.textTheme;
    final styles = <String, TextStyle?>{
      'displayLarge': textTheme.displayLarge,
      'displayMedium': textTheme.displayMedium,
      'displaySmall': textTheme.displaySmall,
      'headlineLarge': textTheme.headlineLarge,
      'headlineMedium': textTheme.headlineMedium,
      'headlineSmall': textTheme.headlineSmall,
      'titleLarge': textTheme.titleLarge,
      'titleMedium': textTheme.titleMedium,
    };

    for (final entry in styles.entries) {
      expect(entry.value?.color, ink, reason: entry.key);
    }
  }

  test('Day Mode serif styles use day ink', () {
    expectSerifStylesUseInk(AppTheme.day());
  });

  test('Moon Mode serif styles use moon ink', () {
    expectSerifStylesUseInk(AppTheme.bedtime());
  });
}
