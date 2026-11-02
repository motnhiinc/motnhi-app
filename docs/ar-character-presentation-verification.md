# AR character presentation — local verification

Date: 2026-10-22. Implementation follows
`superpowers/plans/2026-10-22-ar-character-presentation.md`.

## Environment

- macOS 27.0.1, Apple Silicon; Xcode 27.1 (27A9275).
- Flutter 3.47.5, Dart 3.13.4; OpenJDK 17.0.20.1.
- User approved raising the iOS app minimum from 13 to **15** for this toolchain.
- User separately approved seven SDK-pinned transitive lockfile updates; direct
  dependency constraints and native renderer pins remain unchanged. Strict
  `bash ios/flutter_cocoapods.sh pub get --enforce-lockfile` and
  `pod install --deployment` both pass. Use that wrapper for iOS Flutter commands
  so generated plugin metadata stays consistently CocoaPods-based.
- Android SDK 36.0.0; Flutter Doctor reports some Android SDK licenses unaccepted.
- `adb devices -l`: no connected Android devices.
- `xcrun xctrace list devices`: host Mac and simulators only; no physical iOS device.

## Shared regression checks

- `flutter test --no-pub`: **341 passed**, including four new character-catalog
  integrity tests (unique identities, bridge-safe names, both native files,
  stable fallback).
- Reader-only tests (`native_character_reader_test.dart`,
  `native_story_reader_test.dart`, `ar_reader_controller_test.dart`): **28 passed**.
- `flutter analyze`: two warnings in unchanged
  `lib/features/ar/ar_narration_bundle.dart:209,223`
  (`unawaited_return_in_try_block`). No shared Flutter code was changed for this
  implementation.

## Android native verification

The implementation agent ran, with the installed JDK 17:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:compileReleaseKotlin
```

**Passed:** debug APK packaging, release Kotlin compilation, and **92 unit tests**.
Coverage includes presentation/transform/depth policies, asset contracts,
cancel-preview suppression, debug-option forwarding, and playback callback/tracking
gates. Builds/tests were rerun after review fixes. Successful current-player
completion advances/preloads even after Pause/Move/backgrounding but cannot
autoplay without active playback intent; replaced/terminal callbacks are ignored.
Pause remains available during tracking debounce. A tracking gate closing between
adjacent clips pauses rather than reports an audio error.
Release packaging/signing was not performed. Kotlin and renderer dependency pins
were not changed. See `../android/AR_CHARACTER_PRESENTATION_AUDIT.md` for source
audit evidence, implemented behavior, and remaining limitations.

## iOS native verification

- **18 presentation tests passed** in an isolated simulator framework/test target,
  including successful completion followed by interruption/Move before handling.
  These compile actual reader sources, but do not establish Runner/Flutter or
  resource-bundle integration.
- Device/release and simulator/DEBUG Swift type-checks passed for iOS 15 using the
  installed 27.1 SDKs. This is not linking or device execution.
- **Full Runner workspace build and 50 XCTest tests passed** after the approved
  iOS 15/CocoaPods repair and required Flutter UIScene migration. Scene-owned
  bridges use the actual Flutter controller/messenger and retain their channel
  instances across activation. These results include the final reader source set;
  they do not establish physical AR behavior. See `ios-runner-build-blockers.md`
  for exact commands, pinned dependency reconciliation and clean-bootstrap status.
- Full workspace testing was repeated after the seven approved SDK-pin updates:
  **50 passed**, result bundle `ar-followup-final-sdkpins.xcresult` in the approved
  temporary evidence directory. Android debug assembly/tests/release Kotlin
  compilation were also rerun successfully with the aligned dependency graph.
- Source/test/localization project registration and strings pass static review
  and property-list lint. The three initial review findings (initial failure
  recovery, paused status, ready-preview transform) were fixed and re-reviewed.

To reproduce isolated tests without a hard-coded checkout path, install/use the
`xcodeproj` Ruby gem (available with CocoaPods), choose a fresh output directory
outside the repository and a locally available simulator:

```sh
ruby tools/ar_ios_test_project.rb "$OUTPUT_DIRECTORY"
xcodebuild -project "$OUTPUT_DIRECTORY/ReaderNative.xcodeproj" \
  -scheme ReaderNative -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -derivedDataPath "$OUTPUT_DIRECTORY/derived" test CODE_SIGNING_ALLOWED=NO
xcrun swiftc -typecheck -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -target arm64-apple-ios15.0 \
  ios/Runner/ScanAnyPage/ScanGeometry.swift \
  ios/Runner/CharacterReader/CharacterReaderPresentation.swift \
  ios/Runner/CharacterReader/CharacterReaderViewController.swift
```

The isolated harness and current app both target iOS 15, the approved current
product minimum.

## Audit and implementation scope

- Asset/capture tooling: **26 tests passed**, including regeneration equality against the
  checked-in report. See
  `superpowers/audits/2026-10-22-ar-phase-1.md` for the source-confirmed capability
  matrix, all fourteen native assets, and reproducible device protocol.
- Implemented in both readers: responsive localized controls, center placement
  target/footprint and explicit action, live tracking/surface gates, initial
  viewer-facing presentation basis, tracked committed anchors, transactional
  Move/Cancel, retained audio/progress, separate spatial/playback guidance,
  debounced tracking pause, and explicit-only narration resumption.
- Replaced arbitrary animation playback/iOS bobbing with explicit Idle selection.
  Android selects exact GLB `Idle`; iOS validates the unique loaded-root
  `global scene animation` name and known duration before using the baked loop.
  Actual RealityKit enumeration of all seven assets succeeded on macOS and iOS
  simulator; see `superpowers/audits/2026-10-22-realitykit-runtime.md` and
  `tools/ar_enumerate_realitykit.swift` for reproducible evidence. Other importer
  contracts fall back to a stable pose. Idle/speaking share the authored loop;
  there is still **no dedicated talking clip, mouth motion or viseme rig**.
  Animated foot contact, loop quality and +Z facing require physical approval.
- Bounded pinch scale (0.5–1.5 of the 35 cm baseline), vertical-axis rotation and
  localized accessible adjustment/reset controls are implemented on both readers.
  Nested bottom-center pivots retain plane contact mathematically; Move/Cancel
  retain adjustments. Limits and actual animated contact still need device tuning.
- Android uses the source-confirmed SceneView Environmental HDR pipeline; iOS
  retains automatic environment texturing/default grounding. Android now owns one
  supported plane shadow receiver independently of the grid, avoiding duplicates.
  Neither change proves visual quality.
- Native CPU milestone diagnostics distinguish first session callback, model-ready,
  valid placement and confirmation from GPU presentation/camera-ready measurements.
- Capability-gated occlusion experiments are implemented but **default OFF**:
  Android debug intent opt-in requires supported AUTOMATIC depth and a fresh valid
  image before selecting the depth camera material, otherwise flat-camera fallback;
  iOS scene and people experiments have separate DEBUG launch flags and independent
  support checks. These are test paths, not approved production quality tiers.
- Deferred: ready-preview smoothing, authored/approved talking animation,
  physical facing/loop/grounding approval, production depth/people-occlusion quality
  tiers, asset trimming/compression, measured budgets and thermal tuning.
  These items and all physical-device acceptance remain open in the original
  plan; no release checkpoint is signed off.

## Device-dependent sign-off

**Not verified.** Simulators and desktop targets cannot establish physical AR
placement, animation contact/root drift, material response, tracking recovery,
depth artifacts, startup timings, frame pacing, memory, or sustained thermals.
No before/after recordings or 10–15 minute mobile reading runs were captured.
Limited Marionette startup inspection was performed on the iPhone 18 Pro / iOS
27.0 simulator after full workspace tests passed: the app launched, its onboarding
widget tree was readable, and a screenshot was captured. No consent/profile data
was submitted. Simulated privacy-link taps reported success but produced no
observable route transition; navigation is **unverified**, not a claimed app bug
or a passed reader-entry test. `get-logs` failed with a service-extension error.
CLI/app Marionette versions were both 0.6.0; no session report directory exists.
Evidence screenshot: `ar-followup-marionette.png` under the temporary evidence
directory. Full-screen reader/device validation must use native/device tooling,
not Flutter widget automation.

Release checkpoints A, B, and C therefore remain open. Use the capability audit
and device protocol alongside the original plan; do not interpret local build or
unit-test results as visual or physical-device acceptance.

## Follow-up device evidence tooling

`tools/ar_device_capture.py` captures raw Android PSS, thermal-service status,
process IDs, device/build details and battery state into a new evidence directory.
Memory is summed from individual PID reports returned by `pidof(package)`; it
does not include differently named service processes. Any unavailable PID report
makes that snapshot's total null rather than silently undercounting.
It does not change device settings, clear logs, record audio/video, or launch/stop
the app. An explicit authorized device serial is required. Review device identifiers
and raw diagnostics before sharing results.

```sh
python3 tools/ar_device_capture.py --serial DEVICE_SERIAL \
  --output /path/to/new-evidence-directory --build-mode profile \
  --character cute_doll_v01 --lighting warm-indoor \
  --duration 900 --interval 10
```

Open the reader yourself and perform the Phase 1 audit's fixed session while the
capture runs. A closed process, unavailable thermal API or failed command produces
null measurements, not zeros or stale samples. First/last PSS remain null if those
snapshots are unavailable. Output includes incremental `samples.jsonl`,
`metadata.json` and `summary.json`; interruption preserves partial evidence even
during metadata initialization. Metadata/summary replacement is atomic, with an
explicit completed/interrupted/failed collection status separate from acceptance.

These samples do **not** establish renderer frame pacing or startup timings.
Capture Perfetto/renderer traces on Android and Instruments on iOS separately;
match recordings and native milestone logs to the same device/build/session.
The collector's fourteen tests cover parsing, unavailable/error/closed-process
cases, null-preserving summaries, safe CLI preconditions, and end-to-end file
generation/refusal to overwrite, multiple-process totals and initialization
interruption using simulated adb responses. No device capture has
been performed in this environment.
