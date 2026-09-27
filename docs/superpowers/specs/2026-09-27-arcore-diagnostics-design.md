# ARCore Availability Diagnostics — Design

## Goal

Expose the underlying Android ARCore availability/startup result when the character reader cannot start, so the team can determine why a device such as the Galaxy S10 is classified as unsupported. Preserve the existing friendly failure experience and avoid changing AR support policy.

## Current behavior

The Android native bridge checks `ArCoreApk.checkAvailability()` and maps the result into a small internal decision (`Supported`, `NeedsInstall`, `Unsupported`, `Retry`, or `Failed`). Flutter receives only a Boolean capability result or a normalized failure code. The original ARCore availability enum and startup exception details are discarded, so the user sees only a generic unsupported message.

## Proposed behavior

Keep the current friendly error title and explanatory text. Add a collapsed **Technical details** disclosure to the AR failure UI. When expanded on Android, it shows a concise diagnostic payload containing:

- Raw ARCore availability enum name from the latest check.
- The app's mapped availability decision.
- A stable failure code for reader startup, if startup was attempted.
- A specific ARCore exception class/code when one is available.

The diagnostic should be captured at the native boundary and passed over the existing Flutter method-channel contract. Avoid presenting stack traces, device identifiers, or unrelated build details. Diagnostics are shown only after failure; normal supported-device flows remain unchanged. iOS continues to show its existing user-facing error without Android-specific diagnostics.

## Data flow and responsibilities

1. Android `ArCoreApkGateway` retains the raw `ArCoreApk.Availability` name alongside the mapped decision, including specific exception classes for failed install/session startup when available.
2. The `isStoryReaderSupported` method-channel response becomes a map containing `supported` and optional diagnostic metadata, so the early capability check does not discard the reason before Flutter displays the failure.
3. `CharacterReaderBridge` includes the latest availability and normalized startup failure detail in `PlatformException.details` when opening the reader fails.
4. Flutter parses the optional details into AR reader state while preserving the existing stable failure code.
5. The shared AR failure dialog (including the scan-any-page flow) renders the current localized message and, when Android diagnostic data exists, an expandable technical-details section.

The existing capability probe remains cheap and does not request installation or launch an AR session. The startup flow continues to perform its current install/retry behavior. This feature reports the reasons those paths already produce; it does not broaden the set of devices considered supported.

## Failure handling

- If the bridge cannot provide diagnostic data, show the existing generic error and omit the disclosure.
- Preserve normalized failure codes used by current app behavior; diagnostic metadata is additive. Update the method-channel tests and Dart fakes alongside the response shape change.
- Do not convert transient availability states into a new unsupported outcome.
- Keep the current ARCore installation and retry behavior unchanged.

## Verification

- Unit-test serialization/mapping of raw availability and failure details through the Android bridge contract.
- Unit-test Flutter parsing and optional disclosure behavior, including missing diagnostics.
- On the affected Galaxy S10, reproduce the failure and capture the displayed raw availability/failure code. Confirm a supported, working Android device still enters AR normally.
- Verify the iOS failure presentation and existing Android user-facing copy remain intact.

## Out of scope

- Replacing ARCore/SceneView or changing SDK/device coverage.
- Adding analytics, remote telemetry, or automatic log upload.
- Changing AR install prompts, retry policy, or supported-device gating.
