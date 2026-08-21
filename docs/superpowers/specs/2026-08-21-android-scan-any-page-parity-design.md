# Android Scan Any Page Parity Design

## 1. Goal

Bring the `Scan any page` voice + AR demo to Android at parity with the existing iOS
implementation, by implementing the two native method-channel bridges the Flutter layer
already depends on. The Dart contract is treated as frozen: Android implements to it
rather than changing it.

Companion spec (iOS): `docs/superpowers/specs/2026-08-14-scan-any-page-voice-ar-demo-design.md`.

## 2. Starting Position

The Android project is already scaffolded and the release-visible app is platform-neutral.
`android/app/src/main/AndroidManifest.xml` declares `INTERNET`, `CAMERA` and `RECORD_AUDIO`,
with `android.hardware.camera` marked not required. `camera`, `just_audio`, `flutter_tts`
and `dio` are all cross-platform, and `ar_scene_controller.dart` already treats iOS and
Android alike.

Only two things are iOS-only, both behind method channels with no Android handler:

- `storybook_ar/scan_any_page`
- `storybook_ar/character_reader`

Both entry points are `kDebugMode`-gated — the route in `lib/core/router/app_router.dart`
and the library button in `lib/features/library/library_screen.dart`. A release Android
build therefore never reaches the missing channels. In a debug Android build, the calls
raise `MissingPluginException`, which `ScanAnyPageController`'s bare `catch (_)` clauses
convert into generic `scan:unknown` / `ar:unknown` failure states.

The iOS branch's physical-device acceptance matrix has never been run. Its design
assumptions are unvalidated on real hardware, including the row tolerance in §6.1.

### 2.1 Target Devices

Two phones, no Android tablet:

| Device | ARCore | Notes |
|---|---|---|
| Google Pixel 6a | Certified | Primary test device. Google device, on the supported list since launch. Tensor G1; watch for thermal throttling under sustained camera plus AR. |
| Nothing Phone 3a | **To confirm** | Nothing's earlier handsets are certified and Nothing OS is close to stock, but this model must be checked against Google's supported-devices list before it is relied on. Secondary device. |

Both are GMS devices, so Play Services is present and the ML Kit Document Scanner and ARCore
dependencies in §10 are satisfiable on both. Both ship well above any plausible `minSdk`.

### 2.1.1 Consequences of phones rather than a tablet

The iOS implementation targets an iPad in landscape. Three things follow:

- **Layout: no work required.** `_PageContent` in `lib/features/scan_any_page/scan_any_page_screen.dart`
  is a `LayoutBuilder` feeding a `SingleChildScrollView` and a `ConstrainedBox(maxWidth: 680)`
  around a single stretched `Column`. The feature screen contains no `Row`, every control is a
  full-width stretched button, and the only fixed sizes are icons well under phone width. On a
  phone the 680 cap never binds and content scrolls, so the keyboard-up OCR review case is already
  handled. No orientation is locked anywhere in `lib/`, and iOS `Info.plist` permits portrait and
  landscape on both idioms. There is no Flutter-side camera preview or AR overlay in this feature —
  the native surfaces cover the Flutter view entirely.
- **Copy: work required.** The screen hardcodes iPad and Mac references that will display verbatim
  on a Pixel, at `scan_any_page_screen.dart` lines 86, 96, 282, 287, 302, 365, 373, 478 and 499 —
  including strings on live Android paths such as "Keep the Mac and iPad on the same Wi-Fi",
  "Move the iPad slowly", and "This demo requires a supported physical iPad". These are neutralised
  to device-agnostic wording ("this device", "your computer") as part of this slice. It is small,
  but it is not nothing, and a demo that tells a Pixel user to check their iPad settings is worse
  than a layout bug because it looks like the wrong app.
- **AR ergonomics: genuinely different.** A table-anchored character viewed on a 6.1-inch
  handheld is a different experience from an iPad propped on the table, and plane detection has a
  smaller sensor and a less steady hold to work with. This is an acceptance-matrix concern, not a
  code concern, but the matrix in §12 is run on a phone and its results should not be read as
  predicting iPad behaviour.

## 3. Scope

### 3.1 In scope

- Android implementation of both method-channel bridges, matching the frozen contract.
- Native page capture and bilingual OCR through Google ML Kit.
- Native ARCore plane detection, anchoring, and a table-anchored speaking character.
- Replacement of the Apple sample 3D asset with one CC0 model used by both platforms,
  including the resulting iOS changes.
- A platform-split correction to the TTS temporary-file directory.
- Neutralising the hardcoded iPad and Mac copy in the feature screen (§2.1.1).
- Android build configuration, manifest entries and AR capability gating.
- JVM unit tests mirroring the existing iOS unit tests.
- A physical-device acceptance matrix for Android.

### 3.2 Out of scope

- Any change to the frozen Dart channel contract or to `ScanAnyPageController`'s state machine.
- Making the feature reachable in release builds. It stays `kDebugMode`-gated on both platforms.
- Android release signing configuration.
- The known-story `PageDetector`, image-target manifest, scan session, or curated AR scene flow.
- Public-traffic hardening, deployment, or store distribution.

## 4. The Frozen Contract

Defined by `lib/features/scan_any_page/native_scan_service.dart` and
`lib/features/scan_any_page/native_character_reader.dart`, and already covered by
`test/native_scan_service_test.dart` and `test/native_character_reader_test.dart`.

| Channel | Method | Success payload | Failure codes |
|---|---|---|---|
| `storybook_ar/scan_any_page` | `scanAndRecognize` | `{"text": String}` | `cancelled`, `camera_denied`, `camera_unavailable`, `capture_failed`, `correction_failed`, `ocr_failed`, `no_text`, `scan_in_progress` |
| `storybook_ar/character_reader` | `openCharacterReader(audioFilePath)` | `"completed"` | `cancelled`, `ar_unsupported`, `ar_failed`, `audio_missing`, `model_missing`, `model_load_failed`, `audio_failed`, `reader_in_progress` |

`cancelled` is special: `NativeScanService` and `NativeCharacterReader` translate it into
`ScanCancelled` / `CharacterReaderCancelled`, which the controller treats as a benign return
to the previous phase rather than a failure.

Returning `{"text": ""}` is safe: the Dart guard in `native_scan_service.dart` converts an
empty or whitespace-only payload into `no_text`.

## 5. Registration and Lifecycle

`MainActivity.configureFlutterEngine()` constructs both bridges against the activity and the
engine's `binaryMessenger`, mirroring `AppDelegate.swift`. `configureFlutterEngine` runs
inside `super.onCreate()`, so the bridges always exist before any subsequent registration
code in `onCreate`.

### 5.1 Activity result plumbing

`io.flutter.embedding.android.FlutterActivity` extends plain `android.app.Activity`, **not**
androidx `ComponentActivity`. `registerForActivityResult` therefore does not exist on
`MainActivity` and cannot be used.

The design uses `startIntentSenderForResult` / `startActivityForResult` with an
`onActivityResult` override on `MainActivity`, dispatching by request code to whichever
bridge owns the call.

**The override must call `super.onActivityResult(...)`.** `FlutterActivity.onActivityResult`
forwards to the plugin delegate; swallowing it breaks activity results for every other plugin
in the app.

The alternative — switching `MainActivity` to `FlutterFragmentActivity` to obtain the modern
Activity Result API — is rejected here because it changes the base class of the activity that
hosts the entire release app in order to serve a debug-only feature.

### 5.2 The single-reply invariant

A `MethodChannel.Result` must be replied exactly once, on the main thread. Replying twice
throws; replying zero times leaves the Dart future pending forever, which strands
`ScanAnyPageController` in `scanning` or `openingAr` with no recovery path in the UI.

iOS enforces this with `OneShotGate` plus `isScanInProgress` / `isReaderInProgress`. Android
mirrors it: each bridge holds a nullable pending `Result`, claimed exactly once, cleared on
every terminating path. In-progress flags live on the bridge instance, so process-death
recreation resets them naturally, and a late activity result arriving with no pending `Result`
is dropped silently rather than replied.

Android also needs the analog of iOS's presentability guard: if the launch cannot happen —
activity not resumed, intent sender unavailable — the bridge replies immediately rather than
waiting for a result that will never arrive. **The two channels use different codes**, matching
iOS: the scanner replies `camera_unavailable`, the reader replies `ar_failed`
(`CharacterReaderBridge.swift:89`). `camera_unavailable` is not in the reader channel's
vocabulary and must never appear on it.

### 5.2.1 Request codes

Both bridges dispatch on `startActivityForResult` request codes owned by `MainActivity`. Use
distinctive values below `0xFFFF`, one each for the scanner and the reader. The ARCore install
flow does **not** get one — see §5.2.2. `super.onActivityResult(...)` is called
**unconditionally**, for owned and unowned codes
alike — plugins ignore codes they do not recognise, and an unconditional call cannot forget a
case. No plugin currently in `pubspec.yaml` uses `onActivityResult`, so present collision risk
is negligible, but the codes are still chosen to be distinctive.

### 5.3 Lifecycle hazards

| Hazard | Handling |
|---|---|
| Activity recreated on rotation while a native activity is in front | Google's scanner activity is not ours to configure. The protections are `MainActivity`'s existing manifest `configChanges` (`AndroidManifest.xml:20`), our own reader activity declaring the same, and the pending-`Result`-as-source-of-truth rule below |
| Process death during scan or AR | No pending `Result` and no live Dart future on re-creation; the controller reconstructs in its initial phase |
| Result arriving after configuration change | The pending `Result` is the single source of truth for whether a reply is still owed |
| Back press inside the scanner or AR view | Mapped to `cancelled` |
| Backgrounding during AR | Session paused; on return the anchor is re-acquired or `ar_failed` is reported |
| ARCore install flow completing | Resume-driven, not result-driven — see §5.2.2 |
| Availability re-poll or install resume landing after the app leaves the foreground | Presentability is re-checked at launch time; `startActivityForResult` is silently dropped from the background on Android 10+, so the bridge replies `ar_failed` rather than wait for a result that will never arrive |

### 5.2.2 The ARCore install flow is resume-driven

`ArCoreApk.requestInstall()` does **not** report through `onActivityResult`. It starts the
installer with a plain `startActivity` and reports the outcome by being **called again once the
host activity resumes**. An earlier draft of this design assigned it a request code and waited
for a result; that branch is unreachable, and taking it orphans the pending `Result` on every
device that has to install the ARCore APK — exactly the failure §5.2 exists to prevent.

The flow is therefore:

- `MainActivity.onPostResume()` forwards to the reader bridge.
- The bridge re-drives `requestInstall` only when a `Result` is pending **and** an install is
  genuinely outstanding, so a resume after a normal reader completion does not re-request.
- The first request prompts (`userRequestedInstall = true`); every later one must not.
- `UnavailableUserDeclinedInstallationException` maps to `cancelled`, not `ar_failed`.
- Attempts are **bounded** (`ArCoreInstallPolicy.MAX_ATTEMPTS`). The documented flow needs two —
  prompt, then confirm on resume. Without a bound, an installer that keeps returning
  `INSTALL_REQUESTED` reproduces the orphaned-`Result` defect. Past the bound the bridge replies
  `ar_failed`. The cost is that a genuinely slow install can expire the budget if the user
  bounces in and out of the app; bounded-and-occasionally-impatient beats unbounded-and-hangable.

## 6. Scanner Bridge

`ScanAnyPageBridge.kt` plus supporting Kotlin files under
`android/app/src/main/kotlin/com/storybookar/storybook_ar/scananypage/`.

1. Build `GmsDocumentScannerOptions` with page limit 1, gallery import disabled, JPEG result.
2. Obtain the start intent from `GmsDocumentScanning.getClient(options)` and launch it via
   `startIntentSenderForResult` (§5.1).
3. Read the single returned page URI, load it via `InputImage.fromFilePath`.
4. Recognise text with ML Kit Text Recognition v2 using the default Latin options, which
   cover Vietnamese diacritics.
5. Join recognised lines in reading order and reply `{"text": ...}`.

### 6.1 Reading-order port

`ios/Runner/ScanAnyPage/TextObservationSorter.swift` sorts lines by `midY` **descending** and
greedily groups them into rows within a `0.02` tolerance. Vision reports normalised
bottom-left-origin coordinates; ML Kit reports pixel `Rect`s with a **top-left** origin.

The Kotlin port therefore sorts **ascending** and expresses the row tolerance as a fraction of
the corrected page image height — the same reference frame iOS uses, since both operate on the
deskewed crop. A literal transliteration would reverse line order on every multi-line page.

Three details of the iOS algorithm must be mirrored exactly, because they change grouping on
borderline rows:

- Each candidate line is compared against the **first** line already in a row, not a running
  centroid.
- The **first** matching row wins, not the closest one.
- Line text is trimmed and **empty or whitespace-only lines are dropped before grouping**
  (`PageScannerViewController.swift:379-386`). This affects which rows form, so it is not cosmetic.
- The joined result is trimmed once more before being returned.

One Android-only addition, not a mirror: ML Kit's `Line.boundingBox` is nullable, a case Vision
does not have. Lines without a bounding box are dropped.

The port carries the same unit tests as `ios/RunnerTests/TextObservationSorterTests.swift`.

**The `0.02` tolerance has never been validated against a real page on either platform.** It
was tuned by unit tests alone. §13 sequences a real-page check before the port so the value
carried into Kotlin is one worth keeping.

### 6.2 Failure mapping

The iOS failure vocabulary is reused for Android's distinct failure paths rather than left
unreachable.

The document scanner reports user cancellation as `RESULT_CANCELED` and is not confirmed to
emit any distinct error result code. "Cancelled" and "failed internally" are therefore not
reliably distinguishable from the result code alone, and the mapping is expressed as an ordered
decision rule rather than a list of conditions, so two implementers cannot diverge:

1. `RESULT_OK` **and** `GmsDocumentScanningResult` parses **and** contains at least one page →
   proceed to OCR.
2. `RESULT_OK` but the result is null or contains zero pages → `capture_failed`.
3. Any other result code → `cancelled`.

| Android condition | Code |
|---|---|
| `getStartScanIntent()` returns a failed Task (Play Services absent or outdated, scanner module undownloadable) | `camera_unavailable` |
| Launch throws `SendIntentException`, or the activity is not resumed | `camera_unavailable` |
| Rule 2 above | `capture_failed` |
| `InputImage.fromFilePath` throws | `capture_failed` |
| Text recogniser task fails | `ocr_failed` |
| Recognised text is empty or whitespace after joining | `no_text` |
| Rule 3 above | `cancelled` |
| A second call while one is in flight | `scan_in_progress` |

`correction_failed` and `camera_denied` have no Android producer: perspective correction and
the camera permission prompt both happen inside Google's Activity, which reports neither
condition distinctly. They remain valid contract codes that Android simply never emits.

### 6.3 Known operational cost

The Document Scanner module is delivered through Play Services and downloads on first use,
requiring network and a short wait on the first scan. It must be warmed up before any live
demonstration, and its absence offline is the `camera_unavailable` path above.

## 7. Character Reader Bridge

`CharacterReaderBridge.kt` plus supporting files under
`android/app/src/main/kotlin/com/storybookar/storybook_ar/characterreader/`.

### 7.0 Hosting model

The reader is a **separate Activity launched for result** from `MainActivity`, mirroring iOS's
full-screen modal presentation. It is not an overlay view over the Flutter surface. This is
stated explicitly because §5.1, §5.2.1 and §5.3 all depend on it and are unimplementable without
it.

- The reader activity returns its terminal outcome in the result `Intent` as an extra: either
  `"completed"` or one of the §11 failure codes.
- `RESULT_CANCELED` with no extra — process kill, crash, system dismissal — maps to `cancelled`.
- The bridge translates that extra into the channel reply and clears the pending `Result`.
- It declares the same `configChanges` as `MainActivity` so rotation does not destroy an active
  AR session.

### 7.1 Capability gate and rendering

- **Capability gate.** `ArCoreApk.getInstance().checkAvailability()` maps `UNSUPPORTED_DEVICE_NOT_CAPABLE`
  and equivalent terminal results to `ar_unsupported`, and `UNKNOWN_ERROR` to `ar_failed`.
  The transient `UNKNOWN_CHECKING` and `UNKNOWN_TIMED_OUT` states are **re-polled on a bounded
  budget** — roughly a 200 ms interval up to a fixed cap — after which the bridge replies
  `ar_failed`. Treating the transients as unsupported would reject supported devices on the first
  call; re-polling them without a cap would loop forever on an offline device and orphan the
  `Result`, which is precisely what §5.2 exists to prevent. Both failure modes are defects.
  `requestInstall()` drives the Play Services for AR installation flow; a user decline maps to
  `cancelled`, not `ar_unsupported`. That flow is resume-driven and bounded — see §5.2.2.
- **Rendering.** ARCore with SceneView (`io.github.sceneview:arsceneview`): horizontal plane
  finding, tap-to-place anchor, `.glb` model with an idle animation.
- **Audio.** `MediaPlayer` on the supplied mp3, guarded by an `AudioFocusRequest`. This is the
  Android counterpart of the AVAudioSession interruption handling added for iOS in `501c43b`.
- **Speaking indicator.** A View overlay above the `ARSceneView`, matching iOS, which also uses
  a UIView overlay rather than blend shapes.
- **Explicit read control, pause and resume**, matching iOS.

### 7.2 Completion semantics

These are non-obvious and must be matched, not reinvented. On iOS:

- The result is replied **on dismissal only**. Audio finishing does **not** close the reader —
  playback completion returns the view to its ready state and the reader stays open.
- The code is `completed` if playback started at least once during the session, `cancelled` if
  it never did. A back press is therefore not automatically `cancelled`.
- The audio path is validated **before** any AR capability check, so `audio_missing` takes
  precedence over `ar_unsupported` when both conditions hold.

### 7.3 Audio path validation

A direct analog of `CharacterReaderAudioPathValidator`. The supplied path must:

- be absolute and non-empty;
- have the exact filename `scan_any_page_narration.mp3`;
- resolve, after canonicalisation, to a location contained within `context.cacheDir`;
- be a regular, readable file.

Anything else replies `audio_missing` without opening AR.

## 8. Shared 3D Asset

`ios/Runner/CharacterReader/toy_drummer.usdz` comes from Apple's AR Quick Look Gallery. Its
`ASSET_LICENSE.md` records it as local prototype only, not approved for redistribution.
Shipping it inside an APK is outside those terms, and ARCore renders glTF rather than USDZ.

The design replaces it on both platforms with a single **CC0** rigged character that has an
idle animation. CC0 specifically, not CC-BY, because CC-BY would require an in-app attribution
surface that is not otherwise part of this work.

- `.glb` is the source of truth, loaded natively by Android.
- A converted `.usdz` is committed for iOS.
- `ASSET_LICENSE.md` is rewritten to document the new asset's origin, licence and retrieval date.

**Stop rule.** If provenance and licence cannot be documented, the asset task halts rather
than substituting an undocumented model.

### 8.1 Conversion risk

glTF-to-USDZ conversion routinely loses skeletal animation. iOS degrades gracefully — the
character reader falls back to a simple bob when no animation is present — which means a failed
conversion would *not* announce itself. The asset gate therefore includes an explicit RealityKit
load-and-animate check of the converted `.usdz` **before** any Android reader work depends on it.

### 8.2 Resulting iOS changes

- Remove `toy_drummer.usdz`; add the converted `.usdz`.
- Update model references in `CharacterReaderViewController.swift`.
- Re-run `ios/RunnerTests/CharacterReaderTests.swift`.
- Re-verify the character reader on the iPad.

A smaller model is preferred: the current asset is 13.9 MB, and Filament contributes several
megabytes of native libraries per ABI.

## 9. Temporary Directory Correction

`lib/features/scan_any_page/tts_client.dart` resolves its output directory through
`Directory.systemTemp`.

**On iOS this is correct and must not change.** `Directory.systemTemp` resolves via `TMPDIR` to
the sandbox `tmp/` directory, which is exactly what `CharacterReaderAudioPathValidator` checks
containment against.

**On Android it is broken today.** Dart resolves `Directory.systemTemp` from `TMPDIR` and falls
back to a location the application cannot write, so the TTS write throws and surfaces as
`tts:unknown`.

**`path_provider` is not a drop-in replacement.** On iOS, `getTemporaryDirectory()` returns
`Library/Caches`, **not** `NSTemporaryDirectory()` — verified in
`path_provider_foundation-2.5.1/.../PathProviderPlugin.swift`, where `case .temp` returns
`cachesDirectory`. Adopting it uniformly would move the mp3 to a directory the Swift validator
rejects, producing `audio_missing` on every iOS reader open, with the UI's recovery action
regenerating into the same wrong directory — an unbreakable loop.

**The design therefore platform-splits the injection:**

- iOS keeps `Directory.systemTemp`. No iOS behaviour changes.
- Android uses `path_provider`'s `getTemporaryDirectory()`, which resolves to `context.cacheDir`
  and satisfies the Android validator in §7.3.

Two mechanical consequences:

- `HttpTtsClient` takes a synchronous `Directory Function()`, while `getTemporaryDirectory()` is
  asynchronous. **On Android only**, the directory is resolved once during startup and injected as
  a closure over the cached value, following the existing pattern in `lib/main.dart` where
  `KeyValueStore.create()` is awaited and overridden into the provider graph to keep the rest
  synchronous. Concretely the injection is `Platform.isAndroid ? () => cachedCacheDir : null`,
  where `null` leaves `HttpTtsClient`'s existing `Directory.systemTemp` default in place. Resolving
  `getTemporaryDirectory()` unconditionally on both platforms reintroduces exactly the iOS bug this
  section exists to prevent.
- `path_provider` is currently only a transitive dependency and must be promoted to a direct
  dependency in `pubspec.yaml`.

Write-then-rename behaviour, operation serialisation and `dispose()` ownership semantics are
unchanged, and existing `test/tts_client_test.dart` coverage continues to apply through the
injected directory.

## 10. Build Configuration

- **`minSdk` = 24, verified.** Set explicitly rather than inherited. The concern that SceneView
  would force 28 did not materialise: the debug manifest merges cleanly at 24 with
  `arsceneview 4.18.0`, ARCore and both ML Kit libraries present.
- **SceneView pinned to 4.18.0, and this is a ceiling, not a preference.** `arsceneview 4.19.0`
  and later declare a *strict* dependency on `kotlin-stdlib 2.4.x`, whose 2.4.0 class metadata the
  project's Kotlin plugin (**2.2.20**, `settings.gradle.kts`) cannot read — Gradle resolves the
  conflict in favour of 2.4.x and the compile then fails with every stdlib symbol unresolved.
  4.18.0 is the newest release constrained to `kotlin-stdlib 2.3.21` (metadata 2.3.0), which this
  compiler accepts. **Raising the SceneView version requires bumping the Kotlin plugin first**, and
  that recompiles the release app, so it is not a local change.
- **Manifest additions**, placed in the **`src/debug/AndroidManifest.xml` overlay**, not the main
  manifest, for the reason in §10.1:
  - `<meta-data android:name="com.google.ar.core" android:value="optional"/>`
  - `<uses-feature android:name="android.hardware.camera.ar" android:required="false"/>`
- `optional` and `required="false"` are deliberate: even within debug builds, devices without AR
  support must still install and use the library, player, questions and bedtime flows.
- **Dependencies** added as `debugImplementation` and pinned to explicit versions: ML Kit Document
  Scanner, ML Kit Text Recognition, ARCore, SceneView.
- Release signing is unchanged and remains a follow-up; the feature is debug-only, so signing
  does not gate this work.

### 10.1 Release build impact

`kDebugMode` gates only the Dart route and button. It does **not** keep native code out of the
release APK: the Kotlin bridges, the ML Kit dependencies, and the ARCore, SceneView and Filament
native libraries all compile into a release build, and the `com.google.ar.core` meta-data ships
in the release manifest. iOS has the same property — only the `.usdz` asset is release-excluded,
per commit `f42008e` — but the size cost on Android is far larger, tens of megabytes across ABIs.

The design eliminates this with `debugImplementation` dependencies plus a **registration façade**,
because "`MainActivity` degrades to no bridges in release" has no mechanism on its own:
`MainActivity` lives in `src/main` and cannot reference classes that exist only in `src/debug` —
that is a release compile error, not a graceful degrade.

The working pattern:

- One façade class with the **same fully-qualified name** in each build type's source set — for
  example `com.storybookar.storybook_ar.ScanAnyPageBridges` with a single `register(activity, messenger)`.
- `src/debug/` holds the real implementation and both bridges.
- `src/release/` **and `src/profile/`** hold no-op stubs with identical signatures.
- `src/main/MainActivity.kt` calls the façade unconditionally and imports nothing from ML Kit,
  ARCore or SceneView.

The `profile` stub is not optional. `android/app/src/` already contains `debug`, `main` and
`profile`; omitting the third stub makes `flutter build --profile` fail to compile, and that
failure appears only when someone profiles, long after this work is merged.

The AR manifest entries move to `src/debug/AndroidManifest.xml` for the same reason — leaving them
in the main manifest ships the `com.google.ar.core` meta-data in release, which is part of the cost
being removed.

If this proves impractical, the fallback is to accept the size cost and record it explicitly. What
is not acceptable is the earlier claim that release builds are unaffected.

## 11. Error Handling

Scanner codes are in §6.2. Character reader codes:

| Condition | Android behaviour | Code |
|---|---|---|
| Audio file missing or outside the cache directory | Do not open AR; checked first | `audio_missing` |
| Reader activity cannot be launched (not resumed, launch throws) | Reply immediately, do not wait for a result | `ar_failed` |
| `checkAvailability()` returns `UNKNOWN_ERROR`, or transients exceed the re-poll budget | Offer retry | `ar_failed` |
| ARCore unsupported or device not capable | Explain the requirement, offer exit | `ar_unsupported` |
| Play Services for AR missing, install declined | Return to the previous phase | `cancelled` |
| Model asset missing from the APK | Do not open AR | `model_missing` |
| Model fails to load or parse | Do not open AR | `model_load_failed` |
| Session fails to start or loses tracking irrecoverably | Retain generated audio, offer retry | `ar_failed` |
| `MediaPlayer` fails to prepare or play | Retain AR view, offer retry | `audio_failed` |
| Dismissed after playback started at least once | Normal completion | `"completed"` |

**Limit of the cancel/failure split.** The ordering the bridges control is exact: `resultCode` is
checked before payload, so a cancel carrying no data is never misreported as a capture failure.
What Android cannot recover is the other direction — a native activity that dies of an internal
error exits `RESULT_CANCELED` with no extra, which is indistinguishable from a user backing out
and is reported as `cancelled`. iOS distinguishes `camera_denied`; Android has no equivalent
signal, because permissions are handled inside Google's scanner UI. Do not describe this as
"cancel and failure are not conflated" without that qualifier.
| Dismissed without playback ever starting | Benign return | `cancelled` |
| A second call while one is in flight | Reject the newcomer | `reader_in_progress` |

Backend, TTS and text-length failures are unchanged: they are handled entirely in Dart by
`HttpTtsClient` and `ScanAnyPageController` and are already platform-neutral.

## 12. Testing

JVM unit tests under `android/app/src/test/`:

- Reading-order joining — axis inversion, first-line row comparison, first-match row selection,
  null bounding box handling.
- Audio path validation — containment, filename, traversal rejection, non-regular files.
- Failure-code mapping from native results to channel error codes.
- The one-shot gate and in-progress flags — the single-reply invariant, which is the part most
  likely to break and the one iOS covers via `ScanGeometryTests`' gate and lifecycle cases.

Note that iOS's three test files are the sorter, geometry/gates/lifecycle/stability, and the
character reader — **no iOS test covers failure-code mapping**, so that Android test has no iOS
counterpart to copy and is written from the contract.

Dart tests are unchanged apart from coverage of the injected temporary directory. No
instrumentation, widget, integration or end-to-end suites are run as part of implementation.

Device verification uses an Android translation of the iOS acceptance matrix:

1. English large-text page captures and OCR is editable.
2. Vietnamese diacritics survive OCR or are correctable.
3. Mixed English/Vietnamese text is sent in one request and produces one clip.
4. No backend request occurs before text confirmation.
5. Backend-unreachable retry retains text.
6. TTS failure does not silently fall back to on-device TTS.
7. AR failure and retry do not regenerate speech.
8. Table placement, stable anchor, explicit read, pause/resume, idle motion and speaking
   indicator all work.
9. Reset deletes the temporary audio and returns to entry.
10. Existing release-visible flows are unaffected.

## 13. Delivery Sequence

Ordered so the highest-uncertainty items are answered first, and so shared-design flaws surface
before Android work is built on top of them.

1. **Confirm the Nothing Phone 3a against Google's ARCore supported-devices list**, and read
   SceneView's actual minSdk from the pinned artifact. The Pixel 6a is already known-supported and
   is the primary device, so this step no longer gates the AR work — it only decides whether the
   second device is usable for testing.
2. **Temporary-directory correction**, verified on Android *and* regression-tested on iOS by
   running `openCharacterReader` on the iPad. This catches §9-class breaks immediately rather
   than at step 6.
3. **Asset gate** — source, licence and convert the CC0 model, including the RealityKit
   load-and-animate check of the converted `.usdz` from §8.1, before Android depends on it.
4. **One iPad session running only the scanner on real English and Vietnamese pages**, to settle
   the §6.1 row tolerance before it is ported. Roughly an hour, and it prevents tuning the same
   constant twice in two languages.
5. **Implement the scanner bridge** and validate against real English and Vietnamese pages. This
   is where ML Kit's diacritic quality is answered.
6. **Implement the character reader bridge.**
7. **Re-verify iOS** against the replaced model.
8. **Run the Android acceptance matrix**, then the outstanding full iPad acceptance matrix.

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Nothing Phone 3a not ARCore-certified | Loses the second test device; Pixel 6a unaffected | Step 1 list check |
| Pixel 6a thermal throttling under sustained camera plus AR | Frame rate degrades during a long demo | Watch for it in the §12 matrix; keep AR sessions short |
| Phone-only testing hides iPad-specific AR behaviour | Android matrix passes, iPad still unproven | §2.1.1; the iPad matrix stays a separate outstanding item |
| ~~SceneView requires minSdk 28~~ | **Resolved** — manifest merges at 24 with 4.18.0 | — |
| SceneView is pinned below its latest by the project's Kotlin version | Stuck on 4.18.0 until Kotlin is bumped; newer AR APIs unavailable | Documented in §10; revisit only alongside a deliberate Kotlin upgrade |
| ML Kit Vietnamese diacritic quality below Vision's `vi-VN` | Demo quality | Step 5; the editable OCR review field is the standing safety net |
| SceneView version drift; community-maintained, and its predecessor Sceneform was abandoned | Rendering layer instability | Pin the version and confirm maintenance status before implementation; fall back to raw Filament or a static model |
| glTF-to-USDZ conversion silently drops animation | iOS degrades to a bob without announcing failure | Explicit load-and-animate check in step 3 |
| Play Services required for both Document Scanner and ARCore | Non-GMS devices unsupported | Accepted for demo scope |
| Document Scanner module downloads on first use | First scan is slow and needs network | Warm up before any live demonstration; offline path maps to `camera_unavailable` |
| Android validated before the never-run iPad matrix | Shared design flaws found on Android and fixed twice | Steps 2 and 4 pull the shared-assumption checks onto iOS early |

## 15. Acceptance Criteria

- Both Android bridges implement the frozen contract, with every Android failure path mapped to
  a contract code and the two non-producible codes documented in §6.2.
- No code path leaves a `MethodChannel.Result` unreplied or replies twice. In particular, the
  ARCore availability re-poll terminates on a bounded budget rather than looping.
- No code emits a code outside its own channel's vocabulary — notably, `camera_unavailable` never
  appears on the reader channel.
- A release and a profile build both compile with the AR and ML Kit dependencies excluded, and the
  release manifest carries no `com.google.ar.core` meta-data.
- No user-visible string in the feature names a device the user is not holding.
- `onActivityResult` forwards to `super`, leaving other plugins' results intact.
- Recognised page text preserves reading order on multi-line and multi-column pages.
- The temporary-directory correction works on Android with iOS `openCharacterReader` verified
  unchanged on device.
- One documented CC0 model loads and animates on both platforms; no Apple sample asset remains
  in the repo.
- Devices without AR support still install and run the release-visible flows.
- The feature remains unreachable in release builds on both platforms, and the release APK size
  impact is either eliminated per §10.1 or explicitly recorded.
- `flutter analyze` reports no new issues; Dart and JVM unit suites pass.
