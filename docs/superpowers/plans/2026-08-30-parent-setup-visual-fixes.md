# Parent Setup Visual Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shared serif headings use readable theme colors and visually separate the parent setup cards.

**Architecture:** Correct the color at the shared theme source so every existing serif display, headline, and title style follows the active Day or Moon palette. Keep card separation local to onboarding by inserting fixed vertical gaps rather than changing the shared `PaperCard` API or margin behavior.

**Tech Stack:** Flutter, Dart, Material 3, `ThemeData`, `flutter_test`

---

### Task 1: Correct Shared Serif Text Colors

**Files:**
- Create: `test/app_theme_test.dart`
- Modify: `lib/core/theme/app_theme.dart:217-229,402-409`

- [ ] **Step 1: Write the failing theme regression test**

Create `test/app_theme_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the focused test and verify the current theme fails**

Run: `flutter test test/app_theme_test.dart`

Expected: FAIL because the serif style colors are `null` instead of the active `StitchTokens.ink` value.

- [ ] **Step 3: Pass the active ink color into every shared serif style**

In `lib/core/theme/app_theme.dart`, replace the serif assignments with:

```dart
          displayLarge: _serif(57, FontWeight.w600, t.ink),
          displayMedium: _serif(45, FontWeight.w600, t.ink),
          displaySmall: _serif(36, FontWeight.w600, t.ink),
          headlineLarge: _serif(32, FontWeight.w600, t.ink),
          headlineMedium:
              _serif(28, FontWeight.w600, t.ink, height: 1.2),
          headlineSmall:
              _serif(20, FontWeight.w600, t.ink, height: 1.3),
          titleLarge: _serif(22, FontWeight.w600, t.ink),
          titleMedium:
              _serif(17, FontWeight.w600, t.ink, height: 1.3),
```

Replace `_serif` with:

```dart
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
```

- [ ] **Step 4: Run the focused test and verify both themes pass**

Run: `flutter test test/app_theme_test.dart`

Expected: PASS for both Day Mode and Moon Mode.

### Task 2: Separate Parent Setup Cards

**Files:**
- Modify: `lib/features/onboarding/onboarding_screen.dart:96-176`

- [ ] **Step 1: Add gaps between adjacent setup cards**

Add `const SizedBox(height: 12),` immediately after the nickname, age range, story language, and AR `PaperCard` widgets. The microphone card already has 16px separation from the following consent block, so it does not need a trailing gap.

Apply these exact insertions at the existing card boundaries:

```diff
                 ],
               ),
             ),
+            const SizedBox(height: 12),

             // Age range pills.
```

```diff
                 ],
               ),
             ),
+            const SizedBox(height: 12),

             // Story language pills.
```

```diff
                 ],
               ),
             ),
+            const SizedBox(height: 12),

             // Permissions.
```

```diff
                 subtitle: Text(s.arToggleOnboardingSub,
                     style: Theme.of(context).textTheme.bodySmall),
               ),
             ),
+            const SizedBox(height: 12),
             PaperCard(
               child: SwitchListTile(
```

- [ ] **Step 2: Format the changed Dart files**

Run: `dart format lib/core/theme/app_theme.dart lib/features/onboarding/onboarding_screen.dart test/app_theme_test.dart`

Expected: all three files are formatted successfully.

- [ ] **Step 3: Run focused static analysis**

Run: `flutter analyze lib/core/theme/app_theme.dart lib/features/onboarding/onboarding_screen.dart test/app_theme_test.dart`

Expected: exit code 0 with no analyzer errors.

- [ ] **Step 4: Review the final diff for scope**

Run: `git diff -- lib/core/theme/app_theme.dart lib/features/onboarding/onboarding_screen.dart test/app_theme_test.dart`

Expected: only the serif color parameter, four onboarding gaps, and focused theme tests are present.
