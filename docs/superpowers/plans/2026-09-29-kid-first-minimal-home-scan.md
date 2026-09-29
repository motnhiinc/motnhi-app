# Kid-first Home and Scan Implementation Plan

> **For agentic workers:** Execute the tasks inline in this session. Preserve unrelated working-tree changes; do not commit without an explicit request.

**Goal:** Ship the approved less-is-more Home, scanning cue, and parent handoff.

**Architecture:** Keep the existing scan pipeline and privacy state machine. Replace child-facing presentation around them; move the full story grid and theme filters to a dedicated browse route, and simplify the iOS scanner's native overlays without changing detection/OCR.

**Tech Stack:** Flutter, Riverpod, go_router, ARB localization, Swift/AVFoundation/Vision.

---

### Task 1: Home and library separation

**Files:** `lib/features/library/child_home_screen.dart`, `lib/features/library/browse_stories_screen.dart`, `lib/features/library/scan_book_illustration.dart`, `lib/features/library/library_providers.dart`, `lib/features/library/my_books_screen.dart`, `lib/core/router/app_router.dart`, `lib/shared/widgets/storybook/floating_nav_bar.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb`.

- [x] Move the existing filter bar and story card into the dedicated browse screen, retaining full-library behavior and story navigation.
- [x] Add `/stories` browse route with filters, complete grid, loading/empty/error states, and a way back to Home.
- [x] Replace Home's filters/full grid with the illustrated scan hero, two actual available story covers, **More stories**, and simplified Home/My books navigation. Preserve parent gate and Moon Mode in My books and Browse.
- [x] Verify at 390×844 and 320×568 in English/Vietnamese that the primary action remains reachable and story cards are tappable.

### Task 2: Flutter scan states

**Files:** `lib/features/scan_any_page/scan_any_page_screen.dart`, `lib/features/scan_any_page/scan_child_states.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb`.

- [x] Replace the consent-off state with the Paper handoff, parent-gated action, and story escape; preserve fresh consent checking before native scan.
- [x] Present preparing, ready, blocked and failed states with one dominant action each and short localized labels. Preserve the approved image/highlight player and retry/cleanup behavior.
- [x] Provide small child-safe error copy while keeping internal debug diagnostics out of release UI.

### Task 3: iOS camera cue

**Files:** `ios/Runner/ScanAnyPage/PageScannerViewController.swift`, `ios/Runner/ScanAnyPage/ScanGeometry.swift`, `ios/RunnerTests/ScanGeometryTests.swift`.

- [x] Replace the long top guidance and secondary status with a short **Scan a page** title and a single bottom cue; use existing detected-rectangle and stability signals for find/closer/steady changes.
- [x] Localize EN/VI cue text from the device locale; retain camera cancellation, automatic capture, orientation updates and correction/OCR data unchanged.
- [x] Exercise cue mapping in a focused simulator native test and compile the iOS app. Android's Google scanner is unchanged. Physical-camera review remains pending.

### Task 4: Verification

**Files:** `test/child_home_screen_test.dart`, `test/scan_child_states_test.dart`, any existing tests affected by route/copy changes.

- [x] Add focused tests for primary/secondary Home actions, actual story selection, consent-off parent handoff, and no Listen on rejected/unready states.
- [x] Run `flutter gen-l10n`, `dart format` on touched Dart files, focused `flutter test`, `flutter analyze`, and native compile/test checks. Review `git diff --check` and intended files.
