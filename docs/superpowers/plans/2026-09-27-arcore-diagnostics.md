# ARCore Availability Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the raw Android ARCore availability and startup failure details in an expandable diagnostic section when the character reader cannot start.

**Architecture:** Preserve the existing friendly error and normalized error codes. Extend the native Flutter method-channel responses with optional diagnostic metadata, carry it through the Dart reader/controller state, and render it as a collapsed technical-details disclosure. Keep the probe side-effect-free, leave iOS without Android-specific detail, and do not change support/install/retry policy.

**Tech Stack:** Flutter/Dart, Kotlin, Flutter MethodChannel, Android ARCore 1.54.0, Flutter widget/unit tests, Android local unit tests.

---

## File map

- Modify `android/app/src/main/kotlin/com/motnhi/app/characterreader/ArCoreGateway.kt`: retain raw availability and capture specific install exceptions.
- Modify `android/app/src/main/kotlin/com/motnhi/app/characterreader/ArCoreAvailabilityMapper.kt`: expose raw enum names with the existing decision mapping.
- Modify `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderBridge.kt`: return diagnostic metadata from the capability probe and attach it to reader-start failure details.
- Modify `android/app/src/test/kotlin/com/motnhi/app/NativeFailureMappingTest.kt` and `android/app/src/test/kotlin/com/motnhi/app/characterreader/CharacterReaderBridgeTest.kt`: assert raw statuses, stable codes, and diagnostics on the wire.
- Modify `lib/features/ar/native_story_reader.dart`: parse typed support diagnostics and preserve native error details on `StoryReaderFailure`.
- Modify `lib/features/scan_any_page/native_character_reader.dart`: retain `PlatformException.details` for the single-clip reader path.
- Create `lib/features/ar/ar_reader_diagnostic.dart`: shared immutable Dart diagnostic type and wire-map parser.
- Modify `lib/features/ar/ar_reader_controller.dart`: hold optional diagnostic data for the support-probe failure and reader-open failure.
- Modify `lib/features/player/story_player_screen.dart`: add the collapsed diagnostic disclosure to the AR failure dialog.
- Modify `test/native_story_reader_test.dart`, `test/native_character_reader_test.dart`, and `test/ar_reader_controller_test.dart`: cover method-channel parsing and state propagation.
- Add: `test/story_player_ar_diagnostics_test.dart`, covering `StoryPlayerScreen`'s AR error presentation.
- Update `lib/l10n/app_en.arb` and `lib/l10n/app_vi.arb` with the disclosure label and diagnostic heading; regenerate localization output using the repo's Flutter localization workflow.

## Task 1: Capture and return Android ARCore diagnostics

**Files:**
- Modify: `android/app/src/main/kotlin/com/motnhi/app/characterreader/ArCoreGateway.kt`
- Modify: `android/app/src/main/kotlin/com/motnhi/app/characterreader/ArCoreAvailabilityMapper.kt`
- Modify: `android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderBridge.kt`
- Test: `android/app/src/test/kotlin/com/motnhi/app/NativeFailureMappingTest.kt`
- Test: `android/app/src/test/kotlin/com/motnhi/app/characterreader/CharacterReaderBridgeTest.kt`

- [ ] **Step 1: Add failing tests for raw availability diagnostics**

In `NativeFailureMappingTest`, assert that diagnostic mapping retains both values:

```kotlin
val diagnostic = ArCoreAvailabilityMapper.diagnostic(
    ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE,
)
assertEquals("UNSUPPORTED_DEVICE_NOT_CAPABLE", diagnostic.availability)
assertEquals("Unsupported", diagnostic.decision)
```

In `CharacterReaderBridgeTest`, update the probe assertions to require a map while preserving the existing behavior that only `Unsupported` answers `supported = false`:

```kotlin
val response = result.successValue as Map<*, *>
assertEquals(false, response["supported"])
assertEquals("UNSUPPORTED_DEVICE_NOT_CAPABLE", (response["diagnostics"] as Map<*, *>)["availability"])
```

Add an open-failure assertion that `result.errorDetails` carries `availability` and `decision` while `result.errorCode` remains `ar_unsupported`. Extend the test `RecordingResult` to save its `details` argument.

- [ ] **Step 2: Run the Android tests and confirm the new assertions fail**

Run: `./gradlew :app:testDebugUnitTest --tests 'com.motnhi.app.NativeFailureMappingTest' --tests 'com.motnhi.app.characterreader.CharacterReaderBridgeTest'`

Expected: compilation/test failures because diagnostics and structured probe responses do not exist yet.

- [ ] **Step 3: Retain the raw availability beside its mapped decision**

Introduce an immutable `ArCoreAvailabilityDiagnostic(availability: String, decision: String)` value in `ArCoreAvailabilityMapper.kt`. Add `diagnostic(availability: ArCoreApk.Availability)` that returns `availability.name` and `map(availability).name`. Keep the existing `map` behavior unchanged.

Change `ArCoreGateway.checkAvailability()` to return the diagnostic value. In `ArCoreApkGateway`, call `ArCoreApk.getInstance().checkAvailability(activity)` once and map that same enum value to avoid mismatching raw and normalized results. Replace the install-only enum return with `ArCoreInstallResult(outcome, cause)`, where `cause` is the caught exception class name or null. Preserve each existing install outcome. Update `FakeArCoreGateway` in `CharacterReaderBridgeTest.kt` to return configurable diagnostics and install results.

- [ ] **Step 4: Include diagnostics in the bridge wire responses**

Change `isStoryReaderSupported` success to return:

```kotlin
mapOf(
    "supported" to (diagnostic.decision != ArCoreAvailabilityDecision.Unsupported.name),
    "diagnostics" to mapOf(
        "availability" to diagnostic.availability,
        "decision" to diagnostic.decision,
    ),
)
```

Store the latest diagnostic while the bridge performs its existing availability/install/retry flow. Extend `finishError` to accept an optional details map and pass it as the third argument to `MethodChannel.Result.error`; retain the same `code` and null message. Include a startup exception class only when one was captured. Extend `RecordingResult` to expose the details map.

- [ ] **Step 5: Run Android unit tests and verify they pass**

Run: `./gradlew :app:testDebugUnitTest --tests 'com.motnhi.app.NativeFailureMappingTest' --tests 'com.motnhi.app.characterreader.CharacterReaderBridgeTest'`

Expected: `BUILD SUCCESSFUL`; all existing gate, retry, install, and error-code assertions remain green.

## Task 2: Preserve diagnostic metadata across the Dart channel boundary

**Files:**
- Modify: `lib/features/ar/native_story_reader.dart`
- Modify: `lib/features/scan_any_page/native_character_reader.dart`
- Create: `lib/features/ar/ar_reader_diagnostic.dart`
- Modify: `lib/features/ar/ar_reader_controller.dart`
- Test: `test/native_story_reader_test.dart`
- Test: `test/native_character_reader_test.dart`
- Test: `test/ar_reader_controller_test.dart`

- [ ] **Step 1: Add failing Dart tests for support results and failure details**

Update the `isSupported` channel tests to return the structured probe response and assert both support and diagnostic values. Add a `PlatformException` test whose `details` is:

```dart
{
  'availability': 'UNSUPPORTED_DEVICE_NOT_CAPABLE',
  'decision': 'Unsupported',
  'cause': 'UnavailableDeviceNotCompatibleException',
}
```

Assert that the `StoryReaderFailure` and `CharacterReaderFailure` preserve the original code and parsed diagnostic fields. Include a compatibility test for absent or malformed details, which must yield null diagnostics without changing the code.

- [ ] **Step 2: Run the focused Flutter tests and confirm they fail**

Run: `flutter test test/native_story_reader_test.dart test/native_character_reader_test.dart test/ar_reader_controller_test.dart`

Expected: failures because the readers currently parse a Boolean and keep only `PlatformException.code`.

- [ ] **Step 3: Add typed optional diagnostic models and parse the channel response**

Create `ar_reader_diagnostic.dart` with immutable `ArReaderDiagnostic` fields `availability`, `decision`, and `cause`, plus a factory that accepts `Map<Object?, Object?>` and returns null for an absent or malformed map. Import it in both reader implementations. In `native_story_reader.dart`, define `StoryReaderSupport(supported, diagnostic)` and change `StoryReader.isSupported()` to return it. Parse the Android map; treat legacy Boolean, null, malformed, platform-error, and missing-plugin replies as unsupported with no diagnostic so non-Android and older native implementations fail safely.

Extend `StoryReaderFailure` with `diagnostic`. Parse `PlatformException.details` using the same parser while preserving `PlatformException.code`. In `native_character_reader.dart`, add the same optional diagnostic field to `CharacterReaderFailure` and parse details without changing cancellation handling.

- [ ] **Step 4: Carry support and open diagnostics in controller state**

Add nullable `diagnostic` to `ArReaderState` and its `copyWith`. In `ArReaderController._run`, inspect `StoryReaderSupport`; for unsupported state call `_fail('ar_unsupported', diagnostic: support.diagnostic)`. When `reader.open` throws `StoryReaderFailure`, call `_fail(error.code, diagnostic: error.diagnostic)`. Keep all existing phase ordering and narration preparation behavior unchanged.

- [ ] **Step 5: Run focused Flutter tests and verify they pass**

Run: `flutter test test/native_story_reader_test.dart test/native_character_reader_test.dart test/ar_reader_controller_test.dart`

Expected: PASS, including legacy/missing-diagnostics paths, and all existing cancellation/progress tests remain green.

## Task 3: Render expandable technical details in the AR failure UI

**Files:**
- Modify: `lib/features/player/story_player_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_vi.arb`
- Test: `test/story_player_ar_diagnostics_test.dart`
- Generated: localization outputs under `lib/l10n/`

- [ ] **Step 1: Add a failing widget test for the disclosure**

Build the existing story-player test route with a fake reader that returns unsupported plus `ArReaderDiagnostic(availability: 'UNSUPPORTED_DEVICE_NOT_CAPABLE', decision: 'Unsupported')`. Assert that the friendly error is present, the raw enum is initially hidden, tapping **Technical details** reveals the enum and mapped decision, and the retry/keep-reading actions retain their current behavior. Add a second case with no diagnostics and assert the disclosure is omitted.

- [ ] **Step 2: Run the widget test and confirm it fails**

Run: `flutter test test/story_player_ar_diagnostics_test.dart`

Expected: the detail disclosure and its diagnostic values are not rendered.

- [ ] **Step 3: Add localized labels and render a collapsed diagnostic disclosure**

Add English and Vietnamese strings for the disclosure label and technical-details heading. Update the AR failure presentation to accept the full `ArReaderState` failure context rather than only the code. Preserve `_arFailureMessage`, current title, and current actions. When diagnostics are non-null, render an `ExpansionTile` (or equivalent accessible disclosure) initially collapsed, listing only non-empty availability, decision, and cause fields as selectable text. When details are absent, render no disclosure.

Run: `flutter gen-l10n`

Then run: `dart format lib/features/ar/native_story_reader.dart lib/features/ar/ar_reader_controller.dart lib/features/scan_any_page/native_character_reader.dart lib/features/player/story_player_screen.dart test/native_story_reader_test.dart test/native_character_reader_test.dart test/ar_reader_controller_test.dart test/story_player_ar_diagnostics_test.dart`

- [ ] **Step 4: Run widget and relevant regression tests**

Run: `flutter test test/story_player_ar_diagnostics_test.dart test/ar_reader_controller_test.dart test/native_story_reader_test.dart test/native_character_reader_test.dart`

Expected: PASS; localized friendly copy and actions are unchanged, raw details are hidden until expanded, and absent details render no empty section.

## Task 4: Verify the S10 diagnostic end to end

**Files:**
- No additional source changes expected unless this device run reveals a contract defect.

- [ ] **Step 1: Build and install the Android debug app on the affected S10**

Run: `flutter run`

Expected: with the S10 connected as the only selected Flutter device, the app starts and the existing AR entry point remains available on the device.

- [ ] **Step 2: Reproduce the unsupported message and expand Technical details**

Expected: the UI shows the raw `ArCoreApk.Availability` status, mapped decision, and any startup cause returned by the native bridge. Record the displayed values together with the S10 model number and Android version for triage.

- [ ] **Step 3: Verify the normal supported-device path**

Run the same AR flow on one known ARCore-supported Android phone.

Expected: AR opens normally, no diagnostic disclosure is shown, and the existing user-facing messages and install/retry behavior are unchanged.

## Plan self-review

- **Spec coverage:** native raw status and startup cause are captured; both capability-probe and open-error paths preserve details; Flutter stores optional diagnostics; the failure UI is expandable and localized; missing details remain safe; Android unit, Dart unit/widget, and physical-device checks are included.
- **Placeholder scan:** no TBD/TODO or unresolved path placeholders remain.
- **Type consistency:** `ArCoreAvailabilityDiagnostic` is the native raw/mapped pair; wire keys are `availability`, `decision`, and optional `cause`; Dart `ArReaderDiagnostic` parses those keys; `StoryReaderSupport` carries the probe result; `ArReaderState.diagnostic` carries it to the dialog.
