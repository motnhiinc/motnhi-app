# Parent Setup Visual Fixes

## Problem

The parent setup title can inherit an unreadable color because the shared serif text styles replace the theme's configured display color with a style whose color is unset. The setup cards are also adjacent with no vertical separation.

## Design

- Give every shared serif display, headline, and title style the active `StitchTokens.ink` color. This keeps text dark in Day Mode and light in Moon Mode.
- Add 12px vertical gaps between the nickname, age range, story language, AR, and microphone cards on the parent setup screen.
- Keep the existing cards and do not add divider lines or global card margins.

## Scope

The theme correction applies to existing serif-style call sites throughout the app. Card spacing changes only on the parent setup screen. No state, navigation, localization, or data-model behavior changes.

## Verification

- Run static analysis for the changed Dart files.
- Confirm the parent setup title uses the Day and Moon `ink` colors.
- Confirm each adjacent parent setup card has a 12px gap.
