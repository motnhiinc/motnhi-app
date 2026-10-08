# See in AR — camera-first UI

## Approved direction

- The user selected the recommended camera-first direction.
- The user requested implementation after the Paper drawing.
- Paper file: https://app.paper.design/file/01M4C1CS0GJ13SMSFYFTJW7MXD
- The file contains iPad reading, iPad placement, and phone reading frames.
- Camera and character illustrations are placeholders, not replacement assets.
- The live camera remains the main screen surface.
- Exit and an AR badge occupy the top corners.
- Guidance and playback occupy one bottom dock.
- The dock uses the app's warm paper surface.
- Coral identifies the primary narration action.
- Page arrows are secondary outlined controls.
- The design has no scrubber or new playback operations.

## File map

### iOS presentation

`ios/Runner/CharacterReader/CharacterReaderViewController.swift`

- Replace the floating control constraints with a contained dock.
- Keep existing button targets.
- Move the guidance text inside the dock.
- Add a display heading and placement status caption.
- Add the top AR badge.
- Use SF Symbols for close, page arrows, and playback state.
- Read the already-bundled Flutter fonts for native labels.
- Keep font fallback local to this view controller.
- Style the placement marker with the same light/sage palette.
- Keep the existing session and audio lifecycle.

### Android presentation

`android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderScene.kt`

- Update only the overlay presentation and its UI helpers.
- Keep ReaderUiState fields and defaults.
- Keep CharacterReaderScreen callback signatures.
- Add a contained bottom dock.
- Add a top AR badge.
- Draw small icons with Compose Canvas.
- Load bundled Flutter fonts through the asset manager.
- Keep the existing SceneView composition.
- Keep the ARCore plane finder and tap hit-test path.

### Plan

`docs/plans/2026-10-08-see-in-ar-ui.md`

- Record scope, interfaces, review cases, and checks.
- Record the durable Paper URL.

## Task boundaries

### Task 1 — design

- Create a new Paper file for this app.
- Use existing app colors and typography.
- Render the three approved screen examples.
- Review screenshot spacing, type, contrast, alignment, and fit.
- Finish Paper working indicators.
- This task is complete before native code changes.

### Task 2 — iOS UI

- Build a vertical dock with title, status, and controls.
- Put page count alongside the dock title.
- Hide page count and page arrows for single-clip mode.
- Preserve ready, playing, paused, and retry button meanings.
- Keep an explicit Close action.
- Let dock content scroll at large accessibility text sizes.
- Keep the dock inside safe-area bounds.
- Do not intercept camera taps outside the dock.
- Derive guidance headings from existing reader state.
- Use no new method-channel payload fields.

### Task 3 — Android UI

- Build the same hierarchy with Compose foundation.
- Limit the dock to 640 dp on tablets.
- Let the primary action use the available row width.
- Give arrow controls fixed touch-target slots.
- Make disabled page controls visibly distinct.
- Add accessibility descriptions to icon-only page controls.
- Respect system-bar and display-cutout insets.
- Allow the dock to scroll when text or viewport is constrained.
- Keep callbacks forwarded without adding behavior.
- Use no new Android dependencies.

## Exact interfaces

### iOS actions

- Close calls the existing `close()` target.
- Read/Pause/Resume/Retry calls the existing `togglePlayback()` target.
- Previous calls the existing `goToPreviousPage()` target.
- Next calls the existing `goToNextPage()` target.
- Page count remains based on `pageIndex` and `pages.count`.
- Wave animation remains based on playback state and actual audio playback.
- Placement remains driven by the existing raycast result.
- Guidance rendering reads the existing text and placement/playback state.
- Story progress and completion callbacks retain their existing types.

### Android actions

- Close forwards `onCloseClick`.
- Primary narration action forwards `onReadClick`.
- Previous forwards `onPreviousClick`.
- Next forwards `onNextClick`.
- `state.controlsVisible` gates playback controls.
- `state.pageLabel.isNotEmpty()` gates story-only UI.
- `state.speaking` controls the speaking indicator.
- `state.readLabel` supplies the primary action label.
- `state.canGoPrevious` and `state.canGoNext` gate arrows.
- `state.guidance` supplies the current message.
- No changes to the activity-to-scene contract are required.

## Task order

1. Read the native screen files and app theme.
2. Create and review the Paper file.
3. Save this plan.
4. Implement the iOS overlay.
5. Implement the Android overlay.
6. Review both diffs against the Paper design.
7. Run native checks available in this workspace.
8. Report verification gaps explicitly.

## Review focus

- A phone must fit the controls without the old fixed-width overflow.
- An iPad must not stretch the dock across the whole camera view.
- A landscape viewport must retain access to every control.
- Accessibility font scaling must not make buttons unreachable.
- Page count must not collide with the serif title.
- Single-clip mode must not expose page navigation.
- First-page Previous must be disabled.
- Last-page Next must be disabled.
- Pausing must retain the placed character.
- Retry must remain available after a later audio failure.
- Guidance must remain useful before the model loads.
- Surface-found guidance must disappear after placement.
- The dock must not create unintended placement taps.
- The camera must receive placement taps outside the dock.
- Existing asset font paths must resolve in native builds.
- Missing fonts must use a readable system fallback.
- Primary action text must contrast with the coral background.
- Normal status text must contrast with the paper background.

## Check list

- Paper screenshots for tablet reading, tablet placement, and phone reading.
- `git diff --check` for whitespace errors.
- Android Kotlin compile through the existing Gradle task.
- iOS simulator build with signing disabled, if toolchain permits.
- Existing pure native reader unit tests when practical.
- No widget, integration, or e2e tests.
- No `flutter run`.
- Device AR placement and camera rendering require user device verification.

## Spec coverage

- Full-screen camera: both native screen implementations.
- Quiet top controls: Close and AR badge.
- Contained guidance: placement and reading messages inside dock.
- Clear primary action: coral Read/Pause/Resume/Retry.
- Secondary navigation: outlined Previous/Next arrows.
- App typography: bundled Nunito Sans and Source Serif 4.
- Small screens: flexible primary action and bounded dock.
- Tablet screens: 640-unit dock width limit.
- Existing reader states: preserved.
- Existing Flutter bridge contract: preserved.

## Verification results

- VERIFIED: final Paper screenshots reviewed for all three frames.
- VERIFIED: `git diff --check` passed.
- VERIFIED: Android `./gradlew --offline -Ptarget-platform=android-arm64 :app:compileDebugKotlin --console=plain` passed.
- VERIFIED: Swift type-check passed for the modified reader and its existing `ScanGeometry.swift` dependency.
- Swift check used the installed simulator SDK, cached Flutter framework, and an iOS 13 simulator target.
- The unqualified Android offline build was blocked by uncached ARMv7 and x86 Flutter engine artifacts.
- Android unit tests were attempted but blocked by uncached `junit:junit:4.13.2`.
- The full iOS simulator build was attempted but blocked by missing CocoaPods file lists and the installed Xcode's deployment-target range.
- UNKNOWN: real-device camera, tracking, placement marker appearance, and touch behavior.
- UNKNOWN: font registration and large-text scrolling on an actual device.
- No widget, integration, or e2e tests were run.
- No `flutter run` was used.
- Existing user changes in `pubspec.yaml` and `pubspec.lock` were preserved.
- Reviewer escalation was unavailable: this session does not expose `hawkeye`.
