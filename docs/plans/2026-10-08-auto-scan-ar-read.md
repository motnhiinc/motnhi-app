# Automatic scan, AR, and narration

## Approved requirements
- Implement both preprocessing and the simpler scanner flow.
- Capture automatically when the page is stable.
- Open AR automatically after capture and audio preparation.
- Place the character automatically, without a placement tap.
- Start narration automatically after placement.
- Keep the placed character fixed in world space.
- Do not track the physical page as it moves.
- Add an explicit Scan next page action inside AR.
- Stop narration and release AR before opening the next scan.
- Remove the Listen versus AR choice from the successful scan path.
- Keep the current narration speed.
- Remove page numbers from spoken content.
- Read numbers in Vietnamese when the page is Vietnamese.

## Existing work
- Two native AR presentation files already have local changes.
- Preserve their dock layout, colors, fonts, and accessibility behavior.
- Apply only additive scan-specific controls and behavior.
- Preserve existing pubspec changes.
- Preserve the existing AR UI plan.
- Do not deploy, push, migrate, or call external services during verification.
- The hawkeye reviewer is unavailable in this session.

## File map
- lib/features/scan_any_page/scanned_page_preprocessor.dart
  - Pure geometry-aware page-number filtering.
- lib/features/scan_any_page/scan_any_page_screen.dart
  - Automatic preparation, AR opening, and scan-next loop.
- lib/features/ar/native_story_reader.dart
  - Optional scanned-page mode and scan-next terminal result.
- backend/app/services/page_narration.py
  - Page-context Vietnamese integer normalization.
- backend/app/routers/speakable_page.py
  - Normalize narration only after existing approval verification.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageScannerActivity.kt
  - Camera preview, stable OCR detection, automatic capture, lifecycle.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageCaptureStability.kt
  - Pure stable-frame rule for automatic capture.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/ScanAnyPageBridge.kt
  - Launch the automatic scanner and reuse final image OCR.
- android/app/src/main/AndroidManifest.xml
  - Register the private scanner activity.
- android/app/src/main/kotlin/com/motnhi/app/characterreader/ReaderHost.kt
  - Forward optional scanned-page mode to the activity.
- android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderBridge.kt
  - Carry mode through launch and return scan-next.
- android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderActivity.kt
  - Automatic reading, next-scan result, full-page replay.
- android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderScene.kt
  - Automatic center-plane placement and scan-next button.
- android/app/src/main/kotlin/com/motnhi/app/characterreader/CharacterReaderResultMapper.kt
  - Recognize scan-next terminal code.
- ios/Runner/CharacterReader/CharacterReaderBridge.swift
  - Pass mode and return scan-next after native dismissal.
- ios/Runner/CharacterReader/CharacterReaderViewController.swift
  - Automatic placement, automatic reading, scan-next button, replay.
- test/scanned_page_preprocessor_test.dart
  - Page-number geometry and retained story numbers.
- test/native_story_reader_test.dart
  - Scan mode and terminal result wire coverage.
- backend/tests/test_page_narration.py
  - Vietnamese number rules and language context.
- backend/tests/test_page_audio.py
  - Approved OCR transformed only for speech, not approval input.
- Native reader test doubles where the host interface changes.
  - Add the optional mode argument without changing existing assertions.
- Android pure stability unit test.
  - Stability reset, movement, text changes, and capture threshold.

## Task boundaries
### Preprocessing
- Keep the image bytes and dimensions exactly as supplied by native OCR.
- Keep retained line geometry and original displayed text unchanged.
- Remove only isolated numeric lines in the outer page margins.
- Require other body text before removing a numeric margin line.
- Reject a scan if no readable text remains.
- Filter before validation so the proof binds the retained lines.
- Do not edit signed approval tokens or their verification rules.
- Normalize narration on the server after proof verification.
- Use the full retained page to choose Vietnamese number rules.
- A numeric-only line inside the body inherits the page language.
- Preserve English-page input.
- Preserve identifiers and ambiguous compound numeric tokens.
- Keep one generated clip per retained OCR line.
- Preserve clip names, order, ZIP limits, and ownership cleanup.

### Automatic scanner
- iOS already performs stable rectangle detection and automatic capture.
- Android launches a private application-owned camera activity.
- Use native Camera2 and the already bundled ML Kit text recognizer.
- Add no camera or vision dependency.
- Require stable text and bounds across multiple observations.
- Show simple Find page and Hold still guidance.
- Provide Back; no shutter, crop review, or confirmation step.
- Capture a high-resolution JPEG after the stability threshold.
- Return an app-cache image path to the bridge.
- Delete the scanner-owned temporary JPEG after decoding.
- Return explicit permission, unavailable-camera, and capture failures.
- Close camera resources on pause, cancellation, and completion.
- Guard asynchronous callbacks against terminal state.

### Flutter orchestration
- Await the AR support probe before deciding the successful path.
- Prepare narration once per scan generation.
- Guard each await with mounted and generation checks.
- Open native reader with scannedPageMode true.
- Keep normal library-story opens at the default false.
- Respect the existing profile AR setting.
- Automatically play audio if AR is unavailable or disabled.
- Keep pause, resume, replay, and next scan in the fallback view.
- Do not show an initial Listen or See in AR choice.
- Await native dismissal before restarting scanning.
- Treat native Close as leaving the scan flow.
- Do not restart scanning on Close or system Back.
- On recoverable AR failure, retain the approved narration fallback.

### Native reader behavior
- Keep all scan-specific behavior behind scannedPageMode.
- Require one page for scanned-page mode.
- Auto-place at a center-screen upward horizontal-plane hit.
- Start audio only after a character has been placed.
- Do not repeatedly place or start playback on subsequent frames.
- Keep manual placement for curated library stories.
- Keep pause, resume, interruptions, and failure retry behavior.
- Keep the anchor after narration completes.
- Keep Scan next page reachable while waiting for a surface.
- Return scan_next only from the explicit scan-next action.
- Release native camera and audio before replying.
- Restart a completed scanned page at its first clip on Replay.

## Exact interfaces
- StoryReader.open adds bool scannedPageMode = false.
- openStoryReader payload adds scannedPageMode only when true.
- StoryReaderResult exposes scanNextRequested for scan_next.
- ReaderHost.launchStoryReader adds scannedPageMode = false.
- Android intent adds a private scanned-page-mode boolean extra.
- Native success payload retains lastPageId and pagesRead.
- Native terminalCode adds scan_next for scanned-page mode.
- Normal completed and cancelled result semantics stay intact.
- Scanner channel retains scanAndRecognize with no request changes.
- Scanner success retains imageBytes, width, height, and lines.
- PageCaptureStability consumes text and normalized text bounds.
- It returns true only at the stable-observation threshold.
- preprocessScannedPage returns a page with retained original lines.
- normalize_page_narration accepts and returns ordered strings.
- Validate and audio HTTP request structures stay intact.

## Task order
1. Inspect active Flutter, native scan, native AR, and speech paths.
2. Confirm the intended AR anchoring behavior with the user.
3. Save this plan before implementation.
4. Add preprocessing rules and focused unit coverage.
5. Extend the scan-specific native reader contract.
6. Add automatic placement, reading, next scan, and replay handling.
7. Replace the Android scanner launch with the automatic camera flow.
8. Connect Flutter automatic orchestration and fallback playback.
9. Run focused tests and static/native compilation checks.
10. Review diffs against requirements and pre-existing changes.

## Review focus
- A footer 13 must never become a spoken clip.
- A story sentence containing 13 must retain its meaning.
- A body line containing only 13 must inherit Vietnamese page context.
- An English page must not be converted into Vietnamese.
- Accented OCR can be Unicode decomposed.
- Dates, decimals, and identifiers must not be silently misconverted.
- Movement or changing pages must reset the auto-capture streak.
- No-text frames must not trigger capture.
- Permission denial must complete the pending native call.
- Backgrounding must not capture or start speech unexpectedly.
- A native reply must happen only once.
- A slow support probe must not strand a ready scan.
- Profile changes must not open AR with stale authorization state.
- No surface found must leave Close and Scan next reachable.
- The character must remain fixed after automatic placement.
- Read completion must retain AR until an explicit user action.
- Scan next must stop speech before the next camera session opens.
- Replay must read all clips, not only the final clip.
- Existing library AR flow must retain manual placement.
- Existing local AR styling changes must remain in the diff.

## Checks and coverage
- Run focused Flutter unit and method-channel tests.
- Run Flutter static analysis without output truncation.
- Run focused backend tests with mocked speech and local test storage.
- Run Android offline Kotlin compilation for android-arm64.
- Run pure Android stability and reader tests if dependencies are cached.
- Run Swift simulator type-check with available SDK/framework paths.
- Run git diff --check.
- Do not run widget, integration, or end-to-end tests.
- Do not run flutter run.
- Real-device camera framing and AR placement need device verification.

## Verification results
- VERIFIED: 39 focused Flutter unit and method-channel tests passed.
- Command: flutter test --no-pub test/scanned_page_preprocessor_test.dart test/native_story_reader_test.dart test/ar_reader_controller_test.dart test/scanned_page_ar_audio_test.dart test/native_scan_service_test.dart
- VERIFIED: all six changed Dart source/test files pass targeted dart analyze.
- Whole-project flutter analyze reported two existing warnings in ar_narration_bundle.dart, lines 209 and 223.
- The new scan-screen lint was corrected; targeted analysis is clean.
- VERIFIED: Python unittest passed three tests, including nine integer subcases.
- Command from backend: python3 -m unittest discover -s tests -p test_page_narration.py -v
- Cases include page-wide language context, decomposed Vietnamese, punctuation, English loanwords, and preserved compound notation.
- VERIFIED: Android offline android-arm64 compileDebugKotlin passed.
- Command from android: ./gradlew --offline -Ptarget-platform=android-arm64 :app:compileDebugKotlin --console=plain
- VERIFIED: the compiled production PageCaptureStability class passed JShell smoke assertions.
- Smoke cases: five-frame threshold, changed text, motion, lost quality, empty text, invalid bounds.
- BLOCKED: Gradle JUnit tests cannot resolve uncached junit:junit:4.13.2 in offline mode.
- BLOCKED: backend pytest and its offline package cache are unavailable.
- The added HTTP audio regression test was not executed.
- Existing backend conftest drops and recreates test schemas; it was not invoked.
- VERIFIED: Swift simulator type-check passed for the reader, its bridge, and ScanGeometry.
- Swift target: arm64-apple-ios13.0-simulator, using the installed simulator SDK and cached Flutter framework.
- This is a type-check result, not a full iOS application build.
- VERIFIED: git diff --check passed.
- VERIFIED: the existing AR dock styling remains present in both edited native readers.
- VERIFIED: the existing pubspec changes and the other AR UI plan were not edited.
- UNKNOWN: device camera orientation, preview sharpness, automatic capture, and AR placement timing.
- UNKNOWN: actual generated speech pronunciation; verification used deterministic normalization, not an external speech request.
- Android captures the framed preview image, crops to the guide, and runs final OCR on that same JPEG.
- It does not provide perspective correction or a crop-review screen.
- Native placement uses the current center-camera horizontal-plane hit after AR tracking starts.
- It does not carry a measured world transform from the separate scanner camera session.
- Page-number filtering is conservative: isolated short numeric lines in the outer 10% margins.
- Vietnamese detection uses page text; mixed-language or accent-free OCR remains heuristic.
- Normalization currently converts plain nonnegative integers up to twelve digits.
- Dates, decimals, signed numbers, leading-zero identifiers, and compound codes are preserved.
- Reviewer escalation was skipped because hawkeye is not available in this session.

## Reviewed evidence
- Active route and native providers: lib/core/router/app_router.dart:107-110 and lib/core/di.dart:90-98.
- Flutter scan screen, scan service, page model, validation client, clip player, AR audio preparation, and reader channel: read in full before edits.
- iOS scanner, geometry, reader view controller, and reader bridge: read in full before edits.
- Android scanner bridge, image decoder, manifest, build configuration, reader scene/activity/bridge/host/result mapper: read in full before edits.
- Backend speech route, speech client, image validation, and relevant audio test fixtures: read in full before edits.
- Added preprocessing and stability rules and their tests: reviewed on disk or in their complete patches.
- Tracked changes were reviewed with git diff; pre-existing AR presentation changes were inspected before edits.
- Other application features, backend auth internals, and deployment scripts were outside this review.

## Follow-up
- Publish the backend normalization change only after explicit user approval.
- Check real iOS and Android devices with short text, a footer 13, an inline 13, and two consecutive pages.
- Confirm the character stays fixed after reading and the scan-next action releases camera/audio before recapture.
- Run the queued backend HTTP and Android JUnit regressions when their test environments are available.
