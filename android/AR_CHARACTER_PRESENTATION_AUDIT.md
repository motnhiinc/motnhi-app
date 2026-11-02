# Android character presentation audit (2026-10-22)

## Placement correction (2026-10-29; supersedes earlier placement/depth notes below)

- Inspected the pinned Maven `sceneview-4.18.0-sources.jar`: `ModelNode.centerOrigin` computes `position += origin * size`, not `-(bounds.center + origin * bounds.halfExtent) * scale`. Removed reliance on that helper. Explicit bottom-center translation now uses the Filament asset bounds, and the parent scales/rotates the translation together with the model. This proves static bounds alignment, not animated/skinned foot contact on hardware.
- Footprint derives from normalized horizontal model bounds plus a 1 cm margin, encloses all yaw rotations, and is used by both the marker and polygon checks. Green means eligible for manual placement; amber means checking.
- Depth sensing is now enabled on supported devices in production, independently of the existing experimental occlusion flag. Target sampling transforms VIEW coordinates to TEXTURE_NORMALIZED, reads a fresh Depth16 3×3 patch with row/pixel strides, and requires five consistent valid pixels. Comparison is against camera-space Z, not ray distance. Mismatches beyond max(4 cm, 3%) invalidate readiness.
- Automatic initial placement on depth-capable phones requires 350 ms of continuous matching depth at the same settled target. Missing depth permits explicit placement only after all plane/parallax/footprint gates; the button is visible when ready. Unsupported phones use the verified-plane path. Move always requires explicit confirmation, including scan mode.
- Surface verification requires 8 cm horizontal camera baseline and 1.5 seconds of stable height; target settling remains 700 ms. Loss, frame gaps, changed surfaces, and height refinements invalidate evidence. Initial camera-tracking failures now show lighting/motion/recovery guidance immediately.
- After placement, follow plane subsumption and check anchor-to-plane distance and polygon containment. Sustained loss of support (700 ms) hides the model, pauses playback once, and offers repositioning. No automatic anchor replacement or invented height correction.
- Unit regression coverage includes offset/centered model grounding at all user scales, rotated footprints, depth sampling/invalid buffers/discontinuities, depth agreement, continuous depth evidence, move confirmation, and contact loss. Debug APK packaging, unit tests, and release Kotlin compilation are checked locally. Physical-device contact, scan latency, coordinate mapping in all rotations, depth performance, and thermal behavior remain unverified: no Android device is connected.

## Pinned renderer source inspected

Maven Central `arsceneview-4.18.0-sources.jar` and `sceneview-4.18.0-sources.jar`, matching the unchanged Gradle dependency. Kotlin and all dependencies remain pinned.

- `ARScene.kt`: `onARFrame` applies `LightEstimator` output to the main light and rebuilds indirect lighting only with sufficient estimate/baseline inputs. Environmental HDR is enabled using this existing pipeline, not an application-owned per-frame texture pipeline. Default lighting remains the fallback. Actual light/exposure transitions need device validation.
- Depth session mode and renderer occlusion default OFF. Debug-only intent boolean `storybook_ar.character_reader.EXPERIMENTAL_DEPTH` opts in: query AUTOMATIC support, inspect effective session config, require camera tracking and a fresh (<=250 ms), nonempty sampled Depth16 image. Missing/invalid depth switches camera stream back to its flat material, never hides the character node. Images are closed. SceneView updates its depth texture before the callback; first-enable performs another supported stream update to avoid an uninitialized texture. This experimental path needs device validation, including the cost of the additional image acquisition and first-enable upload.
- Own one public V1 `PlaneRenderer` attached to the same Filament scene; built-in renderer is disabled. Keep its receiver enabled after placement but set `isVisible=false` to suppress the grid independently. No custom fake contact disc or duplicate shadow receiver is stacked. Renderer updates/destruction use pinned public APIs; actual shadow appearance remains unverified.
- `SceneScope.ModelNode`: `autoAnimate` otherwise plays all animations. Application disables it.
- `ModelLoader.loadModelInstance`: existing suspend loader retained rather than introducing blocking asset parsing in composition.
- `AnchorNode.anchor` setter detaches the previous anchor and updates pose. `destroy` detaches the held anchor. `Node.destroy` recursively destroys children: retain the same anchor/model nodes during repositioning and swap the held anchor, instead of recreating the model's parent.

## Bundled GLB findings

- All six `cute_doll_v01`…`v06` variants have 26 named clips, including Idle, Happy, HappyIdle, combat/movement/death clips and ZZ_ALLAnim. Fox has 12 clips including Idle, Attack, Death and Eating. None is an explicitly authored talking clip.
- Named `Idle` is explicitly selected from actual Filament animator names for idle, speaking and paused states, following all-seven bounded-root Idle findings in the phase-1 audit. Unknown assets without Idle retain a stable pose. `autoAnimate=false` prevents all-clips playback. Actual narration drives the localized speaking/paused state; **there is no dedicated talking clip or talking/mouth mapping**. The pinned named-animation composable starts/stops named clips but exposes no crossfade parameter. All states deliberately retain the SAME looping Idle, so no artificial transition/blend or restart is needed. Visual/root-motion approval on hardware is still pending.
- Dolly mesh Eye_01/Mouth_01 POSITION data lie on +Z (example v01 mouth z approximately 0.387–0.450, eyes 0.360–0.443). Fox hierarchy transforms put Head at world z +2.013 and Tail1…8 at negative z. Both use +Z as authored front; explicit per-asset offsets are zero. Viewer yaw uses camera coordinates transformed into anchor space (not world yaw added to an already rotated anchor).
- Existing 0.35 m largest-dimension normalization and bottom-centered origin retained. Perceived size, foot contact and materials remain device-unverified.

## Implemented behavior

- Full-viewport authoritative center target and surface footprint; live-frame upward-facing tracked-plane/polygon and camera gates; explicit placement, with hit revalidated when request is consumed. No estimated plane is claimed to be a confirmed surface. Preview is intentionally unsmoothed to avoid a displayed/committed position mismatch.
- Move pauses without seeking/recreating MediaPlayer. Old anchor remains until valid confirmation; cancel retains it. Neither cancel, confirm, tracking recovery nor foregrounding auto-resumes narration.
- Pinch scales 0.5–1.5 relative to the existing 0.35 m normalization (0.175–0.525 m largest dimension); two-finger twist changes only vertical-axis yaw. A separate parent transforms the normalized, bottom-centered child including its baked offset, keeping the foot pivot on the anchor. Translation/pitch/roll and tap-to-place remain disabled. EN/VI 48 dp semantic buttons provide smaller/larger, ±15° turn and reset equivalents. Controls are sibling overlays, not children of the gesture surface. Adjustments are disabled during moving/tracking loss. Move/cancel retains scale/yaw; confirm compensates for anchor coordinate-frame heading changes. Limits and gesture/pivot behavior require device tuning/approval.
- `ReaderAR` event-only diagnostics record native elapsed-realtime model-ready, first AR callback, first valid placement hit, first frame after placement and first valid depth, plus depth support/requested/effective mode/HDR. Disposal reports missing timings as null. These are CPU callback milestones, not GPU-present timestamps or measured frame pacing. No per-frame log spam, invented GPU timing or unsupported depth claim.
- Cancel immediately excludes the retained footprint pose from rendering, even before another AR frame arrives. The next non-placement frame clears that pose and placement eligibility. Regression coverage exercises repeated move/cancel cycles with a deliberately retained candidate and verifies that confirmation also hides it.
- Camera plus committed-anchor tracking observed continuously. Sustained loss is debounced at 1.2 seconds, pauses playback and gives actionable spatial guidance separately from playback state. Move remains available for recovery.
- Pause stays enabled during the tracking debounce window; tracking gates only starting/resuming. Successful MediaPlayer completion requires nonterminal/current-player identity independently of playback intent: a success queued before Pause/Move/onPause still advances/preloads the next clip, but captured inactive intent forbids autoplay. Errors still require active intent. Pause/release invalidate autoplay/error intent before player/focus operations; release clears identity before releasing the old player. Valid adjacent-clip completion during tracking loss prepares the next clip and leaves it paused, without presenting an audio error or auto-resuming on tracking recovery. Final completion resets/prepares replay once and retains finished/ready UI without starting; old-player duplicate callbacks are ignored.
- English/Vietnamese Android resources, native system locale selection, safe drawing insets, 48 dp minimum buttons with button semantics, wrapping weighted navigation, separate playback-status row, bounded scrollable regions for compact windows/large fonts. Flutter-selected locale is not passed over the bridge.
- Existing progress/result semantics retained; finished-page replay now resets the segment index so replay starts at the first segment.

## Physical-device work still required

### Practical debug-only depth QA entry

Install the debug APK, then start a **fresh exported MainActivity** with the native opt-in:

```sh
adb shell am start -S -W -n com.motnhi.app/.MainActivity --ez storybook_ar.character_reader.EXPERIMENTAL_DEPTH true
```

Navigate normally through Flutter to either scan-any-page or story AR. `ActivityReaderHost` forwards the flag on both reader launch paths only in DEBUG builds; the bridge wire shape is unchanged. `CharacterReaderActivity` remains non-exported: do not launch it directly with adb. Release ignores this flag. Support/configuration/live-image gates still apply; this command is not evidence of working depth or visual approval. `-S` force-stops the app before launch, so save any in-progress work first.

Clear the opt-in with another fresh launch, then navigate normally again:

```sh
adb shell am start -S -W -n com.motnhi.app/.MainActivity --ez storybook_ar.character_reader.EXPERIMENTAL_DEPTH false
```

The flag belongs to the host launch intent, not a persisted preference. Use fresh launches rather than relying on singleTop/new-intent behavior.

No physical AR device validation performed. Do not treat usability, visual quality, contact shadows, HDR stability, tracking accuracy, thermal/frame pacing, memory, accessibility screen-reader navigation or 10–15 minute sustained performance as passed. Pinch/rotation, Idle and shadow receiver code exist but visual approval is pending. Depth remains experimental/default OFF. Preview smoothing and mouth motion remain unimplemented; no talking or realism-complete claim. Native unit tests cannot exercise Filament/ARCore rendering or MediaPlayer continuity on hardware.

## Automated verification

Queued-completion integration follow-up: separate completion identity from autoplay permission, retaining active-intent errors. Five Robolectric Activity regressions exercise queued successful completion after Pause, Move and onPause through next-clip preload and explicit Resume, paused final-clip reset/duplicate suppression, and terminal-success/paused-error rejection. Added completion policy identity coverage. Full debug APK/unit-test/release-Kotlin rerun: **BUILD SUCCESSFUL, 92 tests passed**. DEBUG host forwarding and scaled move-preview radius preserved. No hardware validation.

Debug QA integration follow-up: added Robolectric host coverage for both reader launch paths with absent, false and true flags while asserting existing payload/request-code routing. Full debug APK/unit-test/release-Kotlin rerun: **BUILD SUCCESSFUL, 86 tests passed**. Preserved the move-preview radius correction (`0.175f * state.transform.scale`). No physical device available.

Follow-up depth configuration review: pinned `ARScene.kt` 1047–1051 reacts to the typed `depthMode` parameter after initialization. Both paths now share a capability-gated requested mode: unknown/unsupported starts DISABLED; supported debug opt-in recomposes the typed parameter to AUTOMATIC. The initialization callback no longer independently enables AUTOMATIC while the typed parameter is DISABLED. Observed session depth mode is logged only on actual frame-observed changes (including any fallback/reset), rather than claiming the first configuration remains effective. Added unknown/unsupported/default-off/supported-opt-in policy regression coverage. Reran debug APK, unit tests and release Kotlin: **BUILD SUCCESSFUL, 83 tests passed**. No physical-device validation.

With `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`, ran `./gradlew :app:assembleDebug :app:testDebugUnitTest :app:compileReleaseKotlin`: **BUILD SUCCESSFUL**. The suite now has 92 tests, including transform/depth-configuration/depth-gating/timing policies, host forwarding, Activity completion-race integration cases and updated all-seven named-Idle contracts, preserving placement/cancel/playback guard coverage. Debug APK packaging and release Kotlin compilation passed; release packaging/signing and hardware runs were not performed. Android Studio's bundled JDK 25 failed during Gradle initialization in the previous pass; the existing installed JDK 17 worked without changing project pins.
