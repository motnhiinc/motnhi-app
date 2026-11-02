# AR Character Presentation Implementation Plan

**Goal:** Make the tabletop reader character easy to place, convincingly grounded, responsive to narration, and stable across supported iOS and Android devices.

**Architecture:** Keep Flutter orchestration and the native RealityKit/ARKit and SceneView/ARCore readers. Implement equivalent presentation behavior in each native reader, with capability-based visual enhancements. Preserve story progress and audio behavior through placement and tracking transitions.

**Status:** Partially implemented, including follow-up code (2026-10-22). Native usability/tracking, bounded scale/yaw controls, explicit Idle selection, Android HDR/independent shadow receiving, default-off occlusion experiments, and reproducible asset/capability/device-evidence tooling are implemented. The user approved an iOS 15 minimum for full app/toolchain integration. Dedicated talking animation, physical visual/occlusion approval, sustained performance budgets, and release sign-off remain open; full-build results are tracked separately. See [implementation and verification scope](../../ar-character-presentation-verification.md), [Phase 1 audit](../audits/2026-10-22-ar-phase-1.md), and [RealityKit runtime enumeration](../audits/2026-10-22-realitykit-runtime.md). Checkboxes below retain the original acceptance scope and are not marked passed solely by source changes or unit tests.

## Current baseline

- iOS uses a center reticle and horizontal raycasts, including estimated-plane fallback; Android places at a tapped detected-plane hit.
- Both normalize the model's largest dimension to 0.35 metres.
- iOS loops the first available animation; Android enables automatic animation. Neither explicitly maps character animation to narration.
- Android requests ambient-intensity light estimation; iOS requests automatic environment texturing.
- Application code does not explicitly configure depth occlusion. Verify SceneView and RealityKit defaults before identifying missing renderer behavior.
- Doll GLBs contain approximately 3,000–3,500 triangles, three materials, and 26 animations each at approximately 4.7 MB per variant.
- Placement correction and post-placement tracking guidance are not explicitly implemented.

## Primary files

- `ios/Runner/CharacterReader/CharacterReaderViewController.swift`: session configuration, placement, animation, controls, audio state, lifecycle.
- `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderScene.kt`: scene configuration, placement, model presentation, overlay.
- `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderActivity.kt`: playback and native lifecycle integration.
- `android/app/build.gradle.kts`: renderer dependencies and compatibility constraints.
- `ios/Runner/CharacterReader/*.usdz` and `android/app/src/main/assets/*.glb`: character assets.
- `lib/features/ar/ar_character.dart`: selectable character identities.
- Native reader bridges and Flutter reader adapters: extend only where shared presentation configuration or localized text must cross the channel.

Extract focused placement, animation, and tracking helpers as behavior grows rather than expanding the existing view/controller indefinitely. Final helper names should follow surrounding conventions.

## Delivery order

1. Establish device baseline and renderer capabilities.
2. Fix controls, placement, facing, and repositioning.
3. Add intentional character animation.
4. Improve lighting and grounding, then optional occlusion.
5. Complete tracking recovery and sustained performance validation.

Tracking gates needed for safe placement belong in phase 2; phase 5 completes the recovery experience. Validate on devices at every phase rather than postponing all visual checks until the end.

## Phase 1 — Baseline and capability audit

- [ ] Record the current reader on available supported Android and iOS devices, covering placement, narration, pause, page changes, and background/resume.
- [ ] Inspect the pinned SceneView 4.18.0 implementation for animation defaults, environment lighting consumption, shadow support, depth configuration, anchor disposal, and model-loader threading.
- [ ] Check RealityKit defaults and supported configuration paths for grounding shadows, scene reconstruction, and people occlusion on the deployment target.
- [ ] Inspect every USDZ and GLB for animation names, rig hierarchy, forward axis, origin, bounds, texture dimensions, material properties, and animation root motion.
- [ ] Measure time to camera, time to model-ready, time to valid placement, frame pacing, memory, and thermal behavior during a repeatable reading session.
- [ ] Capture device model, OS, build mode, selected character, lighting conditions, and enabled capabilities alongside results.

**Acceptance:** A reproducible baseline and an explicit capability matrix distinguish confirmed behavior from assumptions. The existing Kotlin compatibility pin is respected; dependency upgrades require a demonstrated need and separate build verification.

## Phase 2 — Placement and controls

### 2.1 Responsive native controls

- [ ] Replace the fixed horizontal story-control arrangement with a responsive layout that fits narrow portrait phones and tablets.
- [ ] Keep Back, Read/Pause/Resume, Next, and Move character reachable; use a separate row for the speaking indicator or secondary actions when needed.
- [ ] Respect system bars, safe areas, font scaling, accessible labels, and platform touch-target minimums.
- [ ] Route new guidance through native localization or the existing Flutter localization boundary; remove device-specific wording such as “Move the iPad.”

**Acceptance:** No clipping or overlap on supported compact-phone and tablet sizes, including larger text. Controls remain stable when speaking state changes.

### 2.2 Consistent placement preview

- [ ] Use a center-screen target and an explicit placement action on both platforms. Make the visible target the authoritative placement location.
- [ ] Show searching, provisional, and ready states based on the target hit and camera tracking quality, not the existence of a plane elsewhere in the scene.
- [ ] Confirm placement on a tracked upward-facing horizontal surface. An estimated hit may show a provisional preview but must not be described as a confirmed table.
- [ ] Add a lightweight footprint or ghost preview indicating position and approximate size. Smooth preview motion without continually moving the committed anchor.
- [ ] Revalidate the hit and tracking state when the placement action is consumed. Reject stale or invalid results without creating an anchor.
- [ ] Rotate the character around the vertical axis to face the viewer at placement, applying an audited per-asset forward-axis offset.
- [ ] Retain the 35 cm largest-dimension baseline initially; validate each model's perceived size and foot contact before changing the size policy.
- [ ] Verify that committed placement uses a tracked anchor appropriate to the platform. On iOS, review the current reuse of the world-space reticle anchor against an explicit ARAnchor-backed placement.

**Acceptance:** The character appears at the preview, faces the viewer initially, stays fixed as the camera moves, and has its feet on the surface. Invalid placement produces clear guidance and no extra anchors.

### 2.3 Reposition and optional transforms

- [ ] Add Move character, returning to placement preview without resetting story/page progress.
- [ ] Pause narration when entering move mode; preserve the playback position. Resume only on explicit user action.
- [ ] Keep the old placement available until confirmation. Cancel restores it; confirmation replaces it and releases the old anchor.
- [ ] Add bounded pinch scaling and vertical-axis rotation after core placement works. Choose limits from device testing and maintain foot contact while scaling.
- [ ] Ensure manipulation gestures do not trigger placement or intercept playback controls.

**Acceptance:** Repeated move/confirm/cancel cycles create no duplicate characters or anchor leaks. Audio resumes at the retained position and page changes retain placement.

## Phase 3 — Deliberate character animation

- [ ] Define presentation states: idle, speaking, paused, and optional short completion reaction.
- [ ] Select clips by audited names, with per-character mappings where needed. Disable generic automatic playback and avoid using clip order as the contract.
- [ ] Verify that selected clips keep the character near its anchor and do not contain inappropriate root motion or all-animation sequences.
- [ ] Drive speaking from actual successful audio playback, including successive clips within a page, completion, retry, interruption, and lifecycle pause.
- [ ] Blend transitions and prevent an idle flash between adjacent narration clips.
- [ ] Prefer a dedicated talking animation. If absent, use an appropriate subtle gesture clip or author one; do not assume existing `Happy` or `Idle` clips are talking animations.
- [ ] Remove the iOS whole-model bob fallback. Use a stable pose until a supported body/rig animation is available.
- [ ] Audit rig and mouth/blendshape support before adding mouth motion. Treat audio-amplitude motion as a simple speaking cue; true phoneme/viseme synchronization is a later enhancement requiring timing data.
- [ ] Trim unused animation clips only after confirming mappings and validating equivalent GLB/USDZ behavior. Retain source assets and licensing/provenance information.

**Acceptance:** Every selectable character loads on both platforms, uses a known idle state, visibly responds to narration where supported, and stops speaking gestures when audio stops. No foot sinking, root drift, or accidental playback of unrelated clips.

## Phase 4 — Lighting, shadows, and occlusion

### 4.1 Lighting and grounding

- [ ] Integrate ARCore Environmental HDR through the supported SceneView lighting pipeline; confirm estimates actually drive the rendered light/environment rather than only changing session configuration.
- [ ] Provide stable fallback lighting while estimates are unavailable. Avoid abrupt changes in exposure or light direction.
- [ ] Keep iOS automatic environment texturing and verify lighting/material response under daylight, warm indoor light, and dim light.
- [ ] Verify existing grounding shadows before adding a shadow receiver. Add a soft contact-shadow solution where needed, avoiding duplicate shadows.
- [ ] Review texture color spaces, roughness, metallic values, transparency, and texture resolution across both exported formats.
- [ ] Preserve the characters' stylized appearance while improving room-light matching and surface contact.

**Acceptance:** Characters look grounded on real surfaces and respond plausibly to room lighting. Record matched before/after scenes to compare shadow quality and material appearance.

### 4.2 Capability-gated occlusion

- [ ] Android: check Depth API support, configure depth when supported, and verify SceneView's camera/depth rendering path actually occludes virtual content.
- [ ] iOS: evaluate supported scene reconstruction/occlusion and people-occlusion semantics independently. Do not assume all devices support room geometry or that people occlusion resolves small objects and hands reliably.
- [ ] Test foreground objects, people, book edges, moving hands, close-up views, and low-texture surfaces for artifacts.
- [ ] Define fallbacks for unavailable or poor-quality depth. Avoid permanently hiding the character on invalid depth frames.
- [ ] Compare frame pacing and thermal cost before selecting default capability tiers.

**Acceptance:** Supported devices show useful occlusion without excessive edge flicker or missing character regions. Devices without depth retain the complete reading experience. Enablement depends on measured quality and cost, not API availability alone.

## Phase 5 — Tracking recovery and performance

### 5.1 Tracking-aware recovery

- [ ] Observe camera and anchor tracking quality throughout the session, including after placement.
- [ ] Map limited tracking to actionable messages such as improve lighting, move more slowly, or point back toward the placement area.
- [ ] Debounce brief state fluctuations. Keep spatial guidance separate from playback labels so one cannot overwrite the other.
- [ ] Block new placement during invalid tracking. For sustained tracking loss, show recovery guidance and pause narration while preserving its position.
- [ ] Recover the existing anchor where possible. If recovery fails, offer Move character rather than silently placing a duplicate.
- [ ] Verify interruption, background/resume, and session-failure behavior without restarting story progress or automatically resuming narration.

**Acceptance:** Temporary tracking loss recovers cleanly; unrecoverable placement has an understandable correction path. No duplicate anchors, sudden intentional relocation, or lost page/audio position.

### 5.2 Performance and asset tuning

- [ ] Repeat the baseline session in profile/release builds with each proposed quality tier, including a 10–15 minute reading run.
- [ ] Target stable 60 FPS on capable devices where the camera/session supports it; use a stable 30 FPS configuration on constrained devices when appropriate. Record actual frame pacing rather than treating a target as a measured result.
- [ ] Set device-specific startup, frame-time, and memory budgets from phase 1 results before sign-off. Investigate any material regression and repeated-session memory growth.
- [ ] Optimize texture resolution, unused animations, material count, and loading before reducing already-lightweight mesh geometry.
- [ ] Evaluate texture/asset compression only after confirming support across both loading pipelines and acceptable visual output.
- [ ] Reduce optional effects when their sustained thermal or frame-time cost outweighs the visual benefit.

**Acceptance:** Repeated open/close and reposition cycles show no continuing resource growth, and the selected visual tier remains stable during sustained narration.

## Verification strategy

### Targeted automated checks

- [ ] Unit-test meaningful state transitions: placement eligibility, move/cancel/confirm, playback-to-animation mapping, tracking recovery, and capability fallbacks.
- [ ] Reuse existing reader bridge/progress tests to protect cancellation, completion, failure, and page-progress semantics.
- [ ] Add asset validation for mapped clip names and required files where the tooling supports reliable inspection.
- [ ] Build both native readers with their pinned dependencies; run affected native tests and Flutter checks when shared adapters change.

Visual realism, anchoring stability, depth artifacts, and sustained thermals require physical-device checks. Use the Marionette workflow for Flutter entry/navigation testing when exercising the app, and native/device tooling for the full-screen AR readers.

### Physical-device matrix

Cover available devices representing:

| Device class | Required coverage |
|---|---|
| Supported iPhone/iPad without LiDAR | Baseline placement, material/shadow quality, available people occlusion, recovery |
| LiDAR-capable iPhone/iPad | Scene occlusion and its performance cost |
| Mid-range supported Android | Baseline quality, controls, sustained performance, depth if available |
| Higher-end depth-capable Android | HDR, occlusion, full quality tier |
| Supported device without enabled depth | Complete fallback reading experience |

For each relevant tier, test all characters and both story and single-clip entry points. Cover textured and plain tables, bright/dim light, portrait and supported rotations, partial occlusion, rapid movement, background/resume, page changes, and repeated repositioning. Record unavailable device coverage as unverified rather than passed.

## Release checkpoints

- [ ] **Checkpoint A — Usability:** responsive controls, valid preview, initial facing, repositioning, and placement tracking gates verified on both platforms.
- [ ] **Checkpoint B — Character quality:** explicit animation mapping, playback synchronization, grounded feet, and lighting/shadow improvements verified.
- [ ] **Checkpoint C — Robustness:** capability-gated occlusion, tracking recovery, fallback devices, and sustained performance verified.

Each checkpoint should include short before/after recordings, tested-device details, measured performance, and any remaining limitations. Capability-sensitive effects can ship after the core usability improvements.

## References

- ARCore light estimation: https://developers.google.com/ar/develop/lighting-estimation
- ARCore Depth API: https://developers.google.com/ar/develop/depth
- ARCore anchors: https://developers.google.com/ar/develop/anchors
- RealityKit scene understanding: https://developer.apple.com/documentation/realitykit/realitykit-scene-understanding
