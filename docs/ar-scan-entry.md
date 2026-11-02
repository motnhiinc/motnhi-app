# Scan-page AR entry

## User path

Home → Scan a page → approved page / narration ready → **See in AR** →
**Choose your AR friend** → native camera → **Place character** → **Read**.

AR is available in ready, playing, paused, and completed scan states when the
parent's AR setting is enabled and the native story reader reports support.
Unsupported devices retain Listen / Replay and an explanatory message. No
story-library routes are restored; the scan-first navigation remains intact.

## Audio handoff

`ScanPageCoordinator.openAr` pauses local playback, checks support again, and
copies the already approved ordered MP3 clips into an owned `scan-ar-*` folder
under the app's temporary/cache directory. The copied filenames follow the
existing native `ar_<scope>_p1_s<index>.mp3` allowlist. One `ArNarrationPage`
containing those paths is passed through the existing `StoryReader` bridge.

There is no new text submission, speech synthesis, backend endpoint, or backend
deployment. The scan image/text are not included in the AR bridge payload.

Copies are deleted after native playback returns (including cancellation and
failure). Original clips remain available for the normal scan player. Rescan
and route cleanup invalidate preparation before native presentation. If native
AR is already open, cleanup waits for it to return before deleting its files.
Returning from AR does not automatically restart Listen.

The character picker is dismissible. Controls and language changes are locked
while selecting/opening AR to prevent concurrent scan/playback operations.

## Little Buddy preview

Android **debug builds only** add Little Buddy (prototype) to the scan picker.
Its GLB is under `android/app/src/debug/assets/`; release builds and iOS do not
offer that choice. It is static and has no mouth, idle, or wave animation clips.
The debug-only selection is not saved in the production character preference.
The source is 20.6 cm tall, but the existing Android viewer normalizes models to
0.35 units before user scaling; check the displayed size on a real surface.

## Build and test

```sh
flutter test test/scan_ar_reader_test.dart test/scan_ar_screen_test.dart \
  test/scan_page_coordinator_test.dart test/scan_page_integration_test.dart
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://api.workbuddylite.space
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

Physical-device checks still required: ARCore support/install prompts, camera
permission denial/retry, surface placement, facing direction, model lighting,
size, ordered audio playback, Back/Close, and Listen after returning. Widget
and bridge tests do not establish camera/AR rendering correctness.
