# Android page-boundary auto capture with manual fallback

## Approved scope
- User chose actual page-boundary detection (option 2).
- Add a visible manual Capture button.
- Auto-capture on a stable detected page boundary.
- Manual capture works when detection cannot find a reliable boundary.
- Preserve automatic OCR, AR opening, and narration after capture.

## Evidence and current behavior
- PageScannerActivity.kt:239-272 runs OCR on successive TextureView snapshots.
- It turns the guide green when OCR has letters and sufficient text bounds.
- PageCaptureStability.kt:17-31 requires exact text and normalized bounds.
- The latter resets on small OCR differences; the user reports no capture.
- ScannerOverlayView.kt:146-163 labels green as a found page despite OCR-only gating.
- ScanAnyPageBridge.kt:65-132 performs final OCR on the captured JPEG.
- ScannerPreviewGeometry.kt:44-65 maps view coordinates into bitmap coordinates.
- There is no existing local page-border detector in this Android scan path.
- Bundled Google document scanner controls its own multi-step UI, so it cannot
  supply just the live boundary result to this app-owned camera screen.
- No device camera frames are available for tuning in this session.
- hawkeye is unavailable in this session.

## Design choice
- Implement a local, pure Kotlin rectangle-edge detector on sampled luminance.
- It is deliberately conservative; ambiguous or weak borders do not auto-capture.
- A manual Capture button remains available while the preview is live.
- Only a detected four-edge page boundary can start auto-capture.
- Recognition of text happens after an image is captured.
- Stable page corners, not exact recognized words, drive auto-capture.

## File map
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageBoundaryDetector.kt
  - Analyze a small grayscale image inside the visible guide.
  - Select four continuous, high-contrast page edges.
  - Estimate a four-corner quadrilateral.
  - Reject undersized, partly outside, or weak boundaries.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageBoundaryStability.kt
  - Track one candidate quad across several sampled frames.
  - Tolerate small corner movement.
  - Reset on missing/invalid page or layout change.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageScannerActivity.kt
  - Replace preview OCR with downsampled boundary detection.
  - Run border analysis off the main thread.
  - Process result on the UI thread only for the current activity/layout.
  - Capture the full-resolution visible preview when auto or manual fires.
  - Auto-capture the rectified page using the stable quadrilateral.
  - Manual capture crops the visible guide, independent of detection.
  - Keep final OCR and channel result ownership in the existing bridge.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/ScannerOverlayView.kt
  - Add a rounded coral Capture action in the paper dock.
  - Keep Back separate and reachable.
  - Show Find / Found / Hold / Preparing guidance.
  - Green means page border was found, not merely OCR was nonempty.
  - Keep the scan guide fixed as guidance and button states change.
  - Disable the button as soon as capture starts.
- android/app/src/test/kotlin/com/motnhi/app/PageBoundaryDetectorTest.kt
  - Synthetic page borders, textured content, clutter, weak edges.
- android/app/src/test/kotlin/com/motnhi/app/PageBoundaryStabilityTest.kt
  - Stable motion, absent page, layout reset, multiple candidates.
- docs/plans/2026-10-08-page-boundary-auto-manual-capture.md
  - Durable interfaces, order, review focus, and checks.

## Exact interfaces
- PageBoundaryDetector.detect accepts luminance samples from inside the mapped guide.
- The sample width, height, and buffer length must agree.
- It returns PageQuad with four normalized corners or null.
- PageBoundaryStability.observe accepts PageQuad? and returns capture eligible.
- Stability uses a displacement tolerance in normalized bitmap coordinates.
- ScannerOverlayView receives onBack and onCapture callbacks.
- ScannerOverlayView.setGuidance accepts scanner guidance.
- ScannerOverlayView.setCaptureEnabled controls the manual button.
- PageScannerActivity maps the guide into a reduced preview bitmap.
- PageScannerActivity converts the normalized quad into the final bitmap.
- Auto mode applies perspective correction to a four-sided candidate.
- Manual mode crops the visible guide, with no guessed perspective correction.
- Both modes save JPEG in app cache with the existing scan-page- prefix.
- ScanAnyPageBridge still returns the same imageBytes, dimensions, and lines.
- No backend, Flutter, or AR channel changes are required.

## Task order
1. Read complete Android capture path and current scanner presentation.
2. Save this implementation plan.
3. Implement pure boundary detector and stability tracker.
4. Add synthetic tests for page/background and changing page positions.
5. Add manual capture action and accurate UI guidance.
6. Replace preview OCR gating with sampled border analysis.
7. Add perspective-corrected auto capture and guide-crop manual fallback.
8. Check one-shot capture, cancellation, and resource cleanup.
9. Compile Android offline and execute available focused checks.
10. Review this task's diff while preserving earlier local changes.

## Review focus
- One page with clear contrast should produce four ordered corners.
- Book cover text or icons without a page perimeter must not trigger auto.
- Strong background furniture edges must not win over a page in the guide.
- Blank or low-contrast pages should be available through the manual action.
- A page that moves outside the guide must reset stability.
- Small edge jitter should not reset the entire streak.
- A page change or view rotation must reset stability.
- Manual Capture must not depend on OCR or boundary detection.
- Manual capture should snapshot the latest visible frame.
- The guide should match the cropped JPEG on rotated displays.
- Auto correction must not mirror or rotate the page unexpectedly.
- Final OCR sees an upright, readable image or returns the existing error.
- UI state must say what it has actually detected.
- Auto and manual callbacks must not write two files.
- Backgrounding before a worker replies must not restart scanning.
- Bitmap ownership and on-complete recycling must avoid use-after-free.
- On detection failure, the scanner keeps running and manual capture works.
- Back, permission denial, and camera failure must still return one result.
- No external network request or new Android dependency for detection.
- No long-running widget/integration tests, no flutter run.

## Checks
- Android offline arm64 compileDebugKotlin.
- Focused pure Kotlin JUnit when existing cached test dependencies permit.
- If JUnit remains offline-blocked, exercise compiled detector and stability
  against synthetic frames through the local JVM, without app deployment.
- git diff --check.
- Verify final status and isolate all pre-existing work.
- Device camera samples are still required to tune confidence thresholds.

## Spec coverage
- Actual page detection: all four page perimeter edges.
- Auto action: stable detected quad after consecutive frames.
- Manual action: always-visible, reachable button while preview is live.
- KYC-like UX: green when a page is found, then auto-capture.
- Existing scan continuation: same image file and downstream OCR contract.

## Verification results
- VERIFIED: Android offline android-arm64 compileDebugKotlin passed after the detector and capture changes.
- Command from android: ./gradlew --offline -Ptarget-platform=android-arm64 :app:compileDebugKotlin --console=plain
- VERIFIED: JShell exercised compiled production detector and stability classes in nine scenarios.
- Scenarios include page with text-like lines, moved page, small page rejection, missing edge rejection, blank frame rejection, tilted rectangle, jitter tolerance, page movement, and lost page reset.
- VERIFIED: after 30 readable frames with one OCR accent fluctuating, the old rule never captured; the new rule uses page corners and does not depend on OCR text.
- BLOCKED: focused Android JUnit tests could not resolve uncached junit:junit:4.13.2 offline.
- VERIFIED: git diff --check passed.
- UNKNOWN: page border confidence and autofocus timing on the user's actual book/device.
- UNKNOWN: visual result and corrected image orientation on the user's device.
- No external service was called; no flutter run or device installation was performed.
- The old PageCaptureStability class and tests remain on disk; deleting user-created files requires separate explicit confirmation.
- Reviewer consultation skipped because hawkeye is not available in this session.

## Review scope
- Read PageScannerActivity.kt:1-327 and ScannerOverlayView.kt:1-295 before edits; inspected resulting changes.
- Read PageCaptureStability.kt:1-33 and PageCaptureStabilityTest.kt:1-33.
- Read ScannerPreviewGeometry.kt:1-66, ScanAnyPageBridge.kt:1-167, and android/app/build.gradle.kts:1-73.
- Read earlier scanner UI plan and its verification sections.
- Added PageBoundaryDetector, PageBoundaryStability, and their focused native unit test sources.
- Did not inspect backend deployment, curated story player, or unrelated Flutter screens for this Android-only change.

## Follow-up needed
- Rebuild the Android app on the device and test one clear page, a low-contrast page, and a page with a busy background.
- Confirm automatic capture after holding still and manual Capture when no border is detected.
- Check that the saved image contains one upright page and OCR leads to AR narration.
- Run JUnit in an environment with the existing test dependency cached.
- Use real camera samples to tune page-edge thresholds if auto detection is too strict or selects background furniture.
