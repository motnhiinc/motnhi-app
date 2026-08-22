# Release Use-Case Wireframe Atlas Design

## Purpose

Create a single self-contained HTML atlas that documents every release-visible Storybook AR use-case and every implemented UI state. The atlas is a documentation artifact, not a functional clone of the Flutter application.

## Deliverable

- File: `release-use-case-wireframes.html`
- Format: semantic HTML and embedded CSS
- Dependencies: none
- Target frame: iPad landscape
- Scope: release-visible Flutter flows only
- Excluded: the debug-only Scan Any Page prototype and unimplemented roadmap features

Existing HTML artifacts must not be modified.

## Page Structure

The atlas uses a sticky index that links to one board per use-case. Every board contains:

- Use-case goal and entry condition
- Route or modal boundary
- Numbered main flow arranged left-to-right
- Transition arrows and destinations
- Exhaustive implemented state variants beneath the main flow
- Disabled controls and recovery actions
- Day and bedtime differences where behavior changes
- Relevant source file references

Frames use a consistent iPad-landscape scale. The document remains horizontally scrollable in narrow browser windows and includes print-friendly styles.

## Visual Language

The wireframes are deliberately low fidelity:

- Grayscale surfaces and controls
- Limited semantic colors for success, error, disabled, camera, and bedtime states
- Simple geometric placeholders instead of external images
- Clear labels for route, trigger, state, and transition
- Consistent legends, frame titles, spacing, and annotations

No external libraries, fonts, images, build tools, or JavaScript state machine are required.

## Use-Case Boards

### 1. Parent Onboarding

Show the default form, optional nickname, age and language choices, AR and microphone permissions, guardian consent, consent-disabled action, saving state, and save failure with retry guidance.

### 2. Story Library

Show loading, backend error with retry, populated categories, empty age/language/theme results, locked and downloaded cards, missing-cover fallback, child personalization, Grown-ups entry, and day/bedtime variants.

### 3. Story Action Sheet

Show the modal opened from an unlocked story, Read and Scan the Book actions, their destinations, and dismissal back to the library.

### 4. Story Player

Show loading, load error with retry, story not found, normal playback, paused playback, first/final-page control states, sentence highlighting and seeking, missing illustration, TTS fallback notice, AR/question control combinations, page navigation, and final completion dialog.

### 5. Comprehension Questions

Show unanswered, correct, and incorrect states; two- and three-choice layouts; missing-image emoji fallback; Next and Done actions; progress labels; and early dismissal back to the player.

### 6. Curated AR Story Moment

Show story loading, startup error, missing scene, camera preview, camera-unavailable fallback, missing-character fallback, preview-mode label, character interaction, and audio playback.

### 7. Known-Story Scan Preview

Show profile/story loading and failure, manifest loading and failure, no-pages state, camera preview and fallback, simulated page recognition list, selected page, and active page narration.

### 8. Bedtime Mode

Show the library toggle transition, dark theme application, bedtime story session, reduced narration speed, and completion behavior without next-story autoplay.

### 9. Parental Gate

Show a fresh arithmetic challenge, focused numeric input, incorrect answer, regenerated challenge, successful redirect to the parent dashboard, and close back to the child library.

### 10. Parent Dashboard

Show loading, error, zero metrics, absent recent-reading content, empty suggestions, populated metrics, recent stories, recommendations, settings navigation, and lock-and-return-to-library action.

### 11. Reading Settings

Show initial/default rendering, voice and volume sliders, language selection, bedtime preference, AR and microphone controls, controls disabled when no profile exists, privacy card, and day/bedtime appearance.

## Source Of Truth

Wireframe behavior must follow the current implementation, primarily:

- `lib/core/router/app_router.dart`
- `lib/core/theme/app_theme.dart`
- `lib/features/onboarding/onboarding_screen.dart`
- `lib/features/library/library_screen.dart`
- `lib/features/library/story_cover.dart`
- `lib/features/player/story_player_screen.dart`
- `lib/features/player/page_text_view.dart`
- `lib/features/questions/question_sheet.dart`
- `lib/features/ar/ar_story_screen.dart`
- `lib/features/ar/scan_story_screen.dart`
- `lib/features/ar/simulated_page_panel.dart`
- `lib/features/parental_gate/parental_gate_screen.dart`
- `lib/features/dashboard/parent_dashboard_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/shared/widgets/async_views.dart`

The atlas should depict implemented behavior even where product documentation differs from runtime behavior.

## Acceptance Criteria

- One HTML file covers all 11 approved release use-cases.
- Every implemented visual state listed above is represented or explicitly annotated.
- All frames use an iPad-landscape viewport.
- Main transitions and modal boundaries are understandable without reading source code.
- Day and bedtime differences are visible where relevant.
- Debug-only Scan Any Page screens do not appear.
- Existing HTML files are unchanged.
- The page opens directly without network access or a build step.
- The layout is readable in a desktop browser and when printed.
- Source references allow each board to be checked against the Flutter implementation.

## Verification

- Open the HTML directly in a browser and inspect every index link and board.
- Compare each board against the referenced routes and feature screens.
- Confirm there are no external resource requests.
- Confirm the page contains no debug-only Scan Any Page flow.
- Confirm existing untracked HTML artifacts remain unchanged.
