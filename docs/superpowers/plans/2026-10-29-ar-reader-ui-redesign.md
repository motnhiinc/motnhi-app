# AR reader UI redesign — implementation plan

## Goal

Implement the approved camera-first AR reader design with a compact reading dock, secondary controls in a bottom sheet, and focused listening and completion states.

- Design reference: [Approved Paper screens](https://app.paper.design/file/01M63FMWPGWNXVVNDAZAQFA73K)
- First target: Android.
- Physical verification device: Nothing Phone (3a).
- Status: Android UI and automated verification complete. Nothing Phone (3a) visual and AR acceptance verification blocked (no device connected).

## 1. Extract the approved design

- Read exact layout, typography, colors, and component styles using Paper's JSX and computed-style tools. Use screenshots for visual review, not as the source of implementation values.
- Build reusable Compose components for the session header, reading dock, primary and secondary actions, controls sheet, listening dock, and completion dock.
- Use localized English and Vietnamese copy and responsive spacing.
- The Paper background is an existing buddy render standing in for the live AR camera; implementation uses the actual camera and anchored character.

## 2. Define explicit UI states

Separate playback state from the currently open panel so sheet visibility cannot accidentally change playback intent.

| State | Visible controls |
| --- | --- |
| Preparing narration | Preparation status |
| Ready | Read + Talk |
| Reading | Pause + Talk |
| Paused | Resume + Talk |
| Listening | Voice guidance + Cancel |
| Page finished | Next page or Scan next page + Replay |
| Final library page finished | Replay + Exit |
| Tracking lost | Recovery guidance + Reposition |

- Opening a sheet or starting listening pauses narration.
- Closing a sheet or canceling listening returns to the appropriate paused/completed state. Playback never restarts as a side effect of dismissing UI.
- Preserve completion events received while a sheet is open or playback is paused.
- Preparing audio disables unavailable actions without hiding session context.

## 3. Replace the existing overlay

Primary integration file: `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderScene.kt`.

- Extract presentation components into a dedicated UI file alongside the scene, following existing package conventions.
- Replace the stacked buttons with one compact bottom dock.
- Add the minimal header: Close, session status, and More.
- Remove persistent placement instructions after successful placement.
- Keep playback actions in stable positions as state changes.
- Keep the character and its feet unobstructed where possible; verify composition on the physical device.
- Respect camera cutouts, system insets, gesture navigation, and enlarged text. Allow sheets to scroll when required.
- Preserve surface detection, anchors, placement validation, model grounding, and existing playback ownership.

## 4. Implement secondary controls

### More sheet

- Previous/next page navigation when the current flow provides it.
- Move buddy.
- Size & direction.
- Listen without AR when supported by the current flow.
- Done closes the sheet without restarting narration.

### Size & direction panel

- Provide focused size, rotation, and reset controls.
- Retain pinch/twist gestures and offer accessible button equivalents.
- Preserve existing scale limits and foot-pivot behavior.
- Respect tracking readiness when enabling adjustments.

### Move mode

- Pause narration and enter surface-placement mode.
- Show Place and Cancel with actionable surface guidance.
- Require explicit confirmation of the new location.
- Cancel retains the original placement and returns to the paused dock.

The focused adjustment panel and recovery presentation extend the approved visual language; review them visually during implementation.

## 5. Integrate voice and completion

Primary integration file: `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderActivity.kt`.

- Connect the redesigned components to the existing reading, listening, page-navigation, pause, exit, and scanner callbacks.
- Listening replaces the reading dock rather than adding another row of controls.
- Show microphone permission failures, unavailable recognition, and retry guidance inside the dock.
- Library stories show page counts and Next page where applicable.
- Scanned pages omit a total and offer Scan next page when finished.
- Final library completion offers replay and exit.
- Keep the existing bridge/result semantics for Listen without AR and Scan next page.

Resource files:

- `android/app/src/main/res/values/reader_strings.xml`
- `android/app/src/main/res/values-vi/reader_strings.xml`

## 6. Verify behavior and presentation

### Automated regression coverage

Add focused coverage under `android/app/src/test/kotlin/com/motnhi/app/characterreader/` for:

- Playback, sheet, and listening transitions.
- Sheet dismissal and listening cancellation without unintended playback.
- Canceling a move while preserving the original placement.
- Completion received while paused or inside a sheet.
- Tracking loss and recovery without automatic narration restart.
- Library versus scanned-page action availability.

Run from `android/`:

```sh
./gradlew :app:testDebugUnitTest :app:compileReleaseKotlin :app:assembleDebug
```

### Nothing Phone (3a) verification

- Compare the implemented reading, controls, listening, and completion screens against Paper.
- Exercise English and Vietnamese at default and enlarged text sizes.
- Check gesture navigation, display cutout, safe insets, and small-height layouts.
- Test microphone denial, recognition failure, and unavailable voice input.
- Exercise actual surface placement, character adjustment, move/cancel, tracking loss, and recovery.
- Confirm the native Compose UI through device screenshots and interaction; Flutter widget inspection alone does not verify this native screen.
- Record unresolved visual or device-specific issues before declaring completion.

## Acceptance criteria

- The normal reading dock contains only playback and Talk actions.
- Secondary controls appear through deliberate navigation.
- Controls do not overlap, clip, or shift unexpectedly as playback state changes.
- Interactive targets are at least 48 dp and have meaningful accessibility labels.
- Sheets and voice interactions never unexpectedly restart narration.
- Placement and grounding behavior remain intact.
- The four implemented core screens visually match the approved Paper design.
- Android checks pass and physical-device verification is completed or explicitly recorded as blocked.

## Suggested implementation sequence

1. Extract Paper values and establish reusable presentation components.
2. Introduce the UI state mapping and implement the reading dock/header.
3. Add the controls sheet, adjustments, and move-mode presentation.
4. Integrate listening, completion, preparation, and recovery states.
5. Add regression coverage, run build checks, and complete device visual QA.

## Implementation record — 2026-10-29

- Extracted all four approved screens with Paper JSX and the reading header/dock computed styles. Reviewed the four reference screenshots without changing the design file.
- Added `ReaderOverlay.kt`: compact reading, preparing, listening/error, completion, placement, and recovery docks; modal More and focused adjustment sheets; localized English/Vietnamese copy; 48 dp minimum targets; inset-aware, scrollable layouts and large-text action stacking.
- Kept narration ownership in `CharacterReaderActivity`. Panel state is independent of playback; opening secondary controls, listening, moving, and tracking recovery cancels automatic-start intent. Closing a panel never starts playback. Page changes clear the previous page’s completion state.
- Kept the AR surface detection, anchor replacement, placement confirmation, grounding, scale limits, and foot-pivot implementation unchanged.
- Added static Inter regular/medium/semibold fonts from Google Fonts (optical size 14, including Vietnamese) for compatibility with API 24+. License: `android/app/src/main/assets/licenses/Inter-OFL.txt`. Buttons retain the design’s system sans typography.
- Native reader inputs currently contain page/audio metadata but no story title. The dock uses localized “Story time” instead of inventing the reference’s sample title. Story title transport remains a follow-up if required.

### Design values

| Role | Extracted value |
| --- | --- |
| Dock surface / primary ink | `#F7F5EF` / `#202D29` |
| Accent / muted text / secondary action | `#557365` / `#66716B` / `#DCE6DD` |
| Dock radius / padding / horizontal margin | 28 / 22 / 16 dp |
| Header targets / header horizontal margin | 48 / 20 dp |
| Primary action height / radius | Minimum 56 / 18 dp |
| Eyebrow | Inter 600, 13 sp, 16 sp line height, 0.08 em tracking |
| Dock title | Inter 600, 22–24 sp, 28–30 sp line height |
| Sheet radius / horizontal padding | 30 / 24 dp |

### Verification and remaining gates

- Final run of `./gradlew :app:testDebugUnitTest :app:compileReleaseKotlin :app:assembleDebug` passed: **139 tests, zero failures/errors/skips**. This includes 18 new native Compose/render and activity-transition tests. `git diff --check` passed.
- Native Compose tests cover the normal dock, modal dismissal, listening replacement/error guidance, preparing-action disabling, scanned/final-library completion, English enlarged text, and Vietnamese sheet scrolling at 320 × 480 dp with 2× text. Activity tests cover pause/sheet/listening transitions, queued completion, automatic-start cancellation, page changes, move cancellation, and tracking recovery.
- Reviewed native renders in `android/app/build/reader-ui-review/`: `reading.png`, `controls.png`, `listening.png`, `finished.png`, `adjustments.png`, and `recovery.png`. Review verdict: consistent spacing, type hierarchy, contrast, aligned repeated-row lanes, no clipping in the captured layouts, and restrained primary/secondary hierarchy. These renders intentionally contain no AR background; system-inset/device composition remains a physical-device gate.
- Physical verification: **BLOCKED**. `adb devices -l` returned no connected devices. No claim of live camera composition, foot clearance, microphone behavior, safe-inset fidelity, or four-screen visual acceptance on Nothing Phone (3a) is made.
- Before acceptance, run the physical-device checklist above, including both languages, enlarged text, actual placement/move/cancel, tracking recovery, and recognition/permission failures. Local native Compose render tests do not replace this gate.
