# Full Runner simulator verification — 2026-10-22

## Current result

- **Resolved:** iOS deployment-target mismatch, missing RunnerTests xcconfigs,
  missing Runner framework file lists, and inconsistent SPM/CocoaPods metadata.
- **Passed:** full Runner workspace simulator build; all seven CocoaPods
  dependencies installed; subsequent `pod install --deployment` succeeds.
- **Passed after UIScene follow-up:** full XCTest execution, **50 tests / zero
  failures**, including three new scene integration tests. The earlier UIKit
  launch crash described below is resolved.
- Direct package constraints and native plugin versions are unchanged. The user
  approved dropping iOS 13/14 support and raising the minimum to **iOS 15**, then
  separately approved exactly seven SDK-pinned transitive lockfile updates below.
  Full Runner testing was rerun after those updates: **50 passed**, result bundle
  `ar-followup-final-sdkpins.xcresult` under the evidence directory.

Toolchain: Flutter 3.47.5 / Dart 3.13.4; Xcode 27.1 (27A9275);
CocoaPods 1.17.0; iPhone 18 Pro simulator running iOS 27.0.

## Configuration changes

- Shared project Debug/Release/Profile deployment target is 15.0; both Runner
  and RunnerTests inherit it. Podfile declares iOS 15 and floors generated pod
  targets to 15, preventing unsupported lower pod targets on Xcode 27.1.
- Flutter's current migration removes the hard-coded `MinimumOSVersion` from
  `AppFrameworkInfo.plist`. The generated built `App.framework` minimum is
  derived from the configured build target; no stale iOS 13 value remains.
- `ios/flutter_cocoapods.sh` sets the supported
  `FLUTTER_SWIFT_PACKAGE_MANAGER=false` environment override for Flutter
  commands. Debug/Release xcconfigs also export it for Xcode build scripts.
  Flutter 3.47.5 has no separate persistent project feature-config file:
  project configuration otherwise lives in `pubspec.yaml`, which was not edited.
  Global Flutter settings were not changed.
- Podfile rejects SPM-enabled generated metadata with a recovery command,
  instead of silently dropping five locked pods on the next installation.
- Existing reader source/test/localization registrations are preserved.

## Reproduce with the existing locked package configuration

Run from the repository root:

```sh
flutter precache --ios
bash ios/flutter_cocoapods.sh build ios --simulator --debug --config-only --no-pub
```

Then in `ios/`:

```sh
pod install --deployment
```

The first reconciliation used `pod install --no-repo-update`, **not** `pod update`.
After reconciling only verified checksums and the Podfile checksum,
deployment-mode installation passes. All seven original pod dependency/version
entries remain unchanged.

From the repository root:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=6F6A2535-84F3-4189-B6D1-8AC2117DD98C' \
  -derivedDataPath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=6F6A2535-84F3-4189-B6D1-8AC2117DD98C' \
  -derivedDataPath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15 \
  -resultBundlePath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15-tests-serial.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO test
```

Before the UIScene follow-up, build exits **0 / BUILD SUCCEEDED**. Test exits **65** after compiling the app
and test bundle, with:

```text
Early unexpected exit, operation never finished bootstrapping - no restart
will be attempted. (Underlying Error: The test runner crashed before
establishing connection: Runner)
```

Final crash report `~/Library/Logs/DiagnosticReports/Runner-2026-10-22-023107.ips`
shows `EXC_BREAKPOINT / SIGTRAP` on the main thread in
`___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`.
Flutter's configure command also warns that UIScene migration is required for
upcoming iOS versions. This needs app lifecycle work, not a CocoaPods workaround;
AppDelegate/Info.plist/source code were not changed by the build-config owner.
The final serial test log explicitly confirms:

```text
Application failed to launch: UIScene life cycle is required for apps built
with this SDK. See "Transitioning to the UIKit scene-based life cycle" in the
UIKit documentation for more information on migration.
```

The result bundle reports no passed tests; this is **not** a passing XCTest run.
Minimal follow-up: adopt Flutter's UIScene lifecycle in the baseline
`Runner/AppDelegate.swift` and scene manifest, preserving plugin registration
and both native bridges (currently initialized from AppDelegate's window).
This is separate app lifecycle ownership, not a reason to change reader code.
The same launch failure will block Marionette/navigation smoke on this SDK.

Two intermediate reruns timed out collecting simulator diagnostics (120s and
300s). The final command disables parallel clones and verbose failure diagnostics;
it terminates normally with exit 65 in about 20 seconds, reproducing the same
baseline launch failure on the real selected simulator.

## Final source set and app handoff

### UIScene runtime follow-up (final source, 2026-10-22)

- `AppDelegate` now follows the installed Flutter 3.47.5 template:
  `FlutterImplicitEngineDelegate` registers `GeneratedPluginRegistrant` against
  `engineBridge.pluginRegistry`, not the app delegate during launch.
- `SceneDelegate: FlutterSceneDelegate` calls super and then retains both native
  bridges using the actual `Main.storyboard` scene's `FlutterViewController` and
  its binary messenger. The scene manifest disables multiple scenes. Bridges
  weakly reference their presenter and use weak method-channel handlers; the
  scene also keeps only a weak controller identity. Reconnecting the same
  controller or reactivating the scene does not recreate channels or lose pending
  camera/reader results. No native reader/scanner implementation was changed.
- Native reader UIApplication active/inactive observers remain valid. Xcode
  27.1's `UIApplication.h` explicitly recommends
  `UIApplication.didBecomeActiveNotification` / `willResignActiveNotification`
  as alternatives to deprecated app-delegate callbacks. Do not repost those
  notifications from scene callbacks (which would duplicate native transitions).
- New `SceneLifecycleTests` verify the running storyboard scene owns both
  bridges, active/inactive delegate callbacks preserve bridge identities, and
  the manifest configures a single Main scene. These are native integration
  checks, not device camera/AR or end-to-end Dart result-delivery verification.

Both commands below exit **0** on the exact requested simulator; full XCTest
reports **50 tests / 0 failures**, including all existing reader tests:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=6F6A2535-84F3-4189-B6D1-8AC2117DD98C' \
  -derivedDataPath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=6F6A2535-84F3-4189-B6D1-8AC2117DD98C' \
  -derivedDataPath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15 \
  -resultBundlePath /private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15-scene-tests.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO test
```

Product remains the `Runner.app` path below. Evidence in the same temporary
directory: `ar-runner-ios15-scene-build.log`, `ar-runner-ios15-scene-test.log`,
`ar-runner-ios15-scene-tests.xcresult`. Xcode's test-only linker warns that its
XCTest libraries were built for iOS 17 while the test target is iOS 15; tests
pass on iOS 27. This does not establish execution on an iOS 15 device.
The earlier clean-bootstrap limitation was resolved separately with the explicit
SDK-pin approval documented below.

### Earlier pre-migration verification

The final build and serial test were rerun after the native source agent finished.
Git blob hashes at completion:

- `CharacterReaderPresentation.swift`: `6f682999b82251466c5a5344076ca692f08f6332`
- `CharacterReaderViewController.swift`: `29041794030a3048cf662b59f922f9369a5d3fea`
- `CharacterReaderPresentationTests.swift`: `2d1bdfa36c348d4b46e64b6916d71b50465cd757`

App product:
`/private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-runner-ios15/Build/Products/Debug-iphonesimulator/Runner.app`

Exact destination UUID: `6F6A2535-84F3-4189-B6D1-8AC2117DD98C`
(iPhone 18 Pro / iOS 27.0). Runner, App.framework, and RunnerTests built plists
all report `MinimumOSVersion = 15.0`.

## Native pod checksum verification (no native package upgrades)

Each installed `Pods/Local Podspecs/*.podspec.json` was compared semantically
with its source podspec in the symlinked pub-cache package; they match. Each
installed spec's CocoaPods checksum matches the new lockfile. Each package's
own pubspec version matches the existing root `pubspec.lock`:

| Package | Existing Dart version | Pod version |
| --- | --- | --- |
| audio_session | 0.2.3 | 0.0.1 |
| camera_avfoundation | 0.10.1 | 0.0.1 |
| flutter_tts | 4.2.5 | 0.0.1 |
| just_audio | 0.10.5 | 0.0.1 |
| path_provider_foundation | 2.5.1 | 0.0.1 |
| shared_preferences_foundation | 2.5.6 | 0.0.1 |

Flutter pod remains 1.0.0; its installed spec matches the current SDK-generated
podspec (which requires iOS 15). Lock changes are spec/Podfile checksums and the
CocoaPods tool version (1.16.2 → 1.17.0), not dependency resolution changes.

## Clean-bootstrap SDK-pin alignment — resolved with explicit approval

The earlier strict-resolution failure is resolved. The user explicitly approved
only these seven Flutter 3.47.5 SDK-pinned transitive updates; normal `pub get`
preferred all existing locked versions and changed exactly these entries:

| Package | Before | Approved / resolved |
| --- | --- | --- |
| intl | 0.20.2 | 0.20.3 |
| matcher | 0.12.19 | 0.12.20 |
| meta | 1.18.0 | 1.19.0 |
| test | 1.31.0 | 1.31.1 |
| test_api | 0.7.11 | 0.7.12 |
| test_core | 0.6.17 | 0.6.18 |
| vector_math | 2.2.0 | 2.4.3 |

Before resolution, the full existing user lockfile was snapshotted at
`/private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/ar-sdkpins-before.lock`
(Git blob `3c81d29107cfe5e9db69b8c8be0a6832a4902e64`). The resulting lockfile
blob is `1ba07fdc04599926b21128e844d80fab450c1fc0`.

A semantic comparison against that snapshot confirms **only seven package
version + SHA256 changes**: no other package entries, dependency classifications,
sources, SDK lower bounds, direct dependencies, renderer pins, or prior user
changes were modified. `pubspec.yaml` remains byte-identical (Git blob
`dcff966cce104e1c114de2a7ef2ef196259581f9`). Flutter's automatic unrelated
`analysis_options.yaml` migration was removed; that file has no resulting diff.

Reproducible commands (repository root unless indicated):

```sh
bash ios/flutter_cocoapods.sh pub get
bash ios/flutter_cocoapods.sh pub get --enforce-lockfile
# In ios/:
pod install --deployment
# Back at the repository root:
bash ios/flutter_cocoapods.sh test --no-pub
bash ios/flutter_cocoapods.sh analyze --no-pub
```

Results:

- Preferred-lockfile resolution: **exit 0**, `Changed 7 dependencies!`.
- Strict resolution: **exit 0**, `Got dependencies!`, no further lockfile changes.
  Package configuration/plugin metadata were freshly regenerated by Flutter;
  no stale `--no-pub` resolution is needed to bootstrap this SDK anymore.
- CocoaPods deployment installation: **exit 0**, seven dependencies / seven pods,
  no pod version changes. The pre-existing custom Profile xcconfig warning remains.
- Flutter tests: **exit 0, 341 passed**.
- Flutter analysis: **exit 1**, only two `unawaited_return_in_try_block` warnings
  in unchanged `lib/features/ar/ar_narration_bundle.dart` at 209:29 and 223:9.
  No source edits made; the minimal follow-up is review/await those Future returns.

No simulator build or app launch was performed during this dependency-only
verification, avoiding interference with the main agent's Marionette smoke.
The separate UIScene/full-Runner results above are preserved as recorded.

New evidence under
`/private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/`:
`ar-sdkpins-exact-diff.log`, `ar-sdkpins-pub-get.log`,
`ar-sdkpins-enforce-lockfile.log`, `ar-sdkpins-pod-deployment.log`,
`ar-sdkpins-flutter-test.log`, and `ar-sdkpins-flutter-analyze.log`.

## Evidence files

Under `/private/var/folders/kf/l3nhmvsd129_l7wpj0plydzh0000gn/T/opencode/`:

- `ar-ios-configure.log`
- `ar-ios-pub-get.log` (strict resolution failure; no upgrades accepted)
- `ar-ios-pod-install.log`
- `ar-ios-pod-deployment-final.log`
- `ar-runner-ios15-build-final.log` (final source set; success)
- `ar-runner-ios15-test.log`
- `ar-runner-ios15-test-serial.log` (final source set; launch failure)
- `ar-runner-ios15-tests-serial.xcresult` (complete final test result)
