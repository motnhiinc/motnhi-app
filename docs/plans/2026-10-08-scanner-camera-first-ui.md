# Scanner camera-first UI repair

## Approved direction
- User selected option 1: match the application's AR design.
- Replace default Android scanner controls with app-styled controls.
- Use a full-screen live camera.
- Fix preview sizing and rotation.
- Keep automatic capture and the automatic AR reading handoff.

## Current evidence
- The scanner uses a plain Android Button for Back.
- It uses a flat rectangular TextView for guidance.
- Its preview uses minimum scale and changes the TextureView bounds.
- That fit-inside layout leaves black strips on different aspect ratios.
- It also applies sensor rotation to the texture content.
- The screenshot shows a sideways camera image.
- Duplicate sensor rotation is the working diagnosis, not a device-verified result.
- TextureView.getBitmap applies its content matrix before copying the layer.
- This is visible in the installed Android SDK source, lines 699-713.
- The existing AR overlay supplies the presentation reference.
- The existing app theme supplies color and typography tokens.
- The hawkeye reviewer is unavailable in this session.

## File map
- android/app/src/main/kotlin/com/motnhi/app/scananypage/PageScannerActivity.kt
  - Keep camera ownership and scanner result lifecycle here.
  - Replace the inline default controls with the styled scanner overlay.
  - Keep TextureView at full viewport size.
  - Apply tested preview geometry to its content matrix.
  - Map the overlay guide into the captured bitmap coordinate space.
  - Ignore OCR results from an old layout or display rotation.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/ScannerOverlayView.kt
  - Scanner-local native overlay with existing app fonts and colors.
  - Safe-area Back control and compact scan badge.
  - Bounded paper guidance card.
  - Dimmed region outside the readable scan guide.
  - Responsive portrait and landscape layout.
- android/app/src/main/kotlin/com/motnhi/app/scananypage/ScannerPreviewGeometry.kt
  - Pure center-crop and display-rotation calculations.
  - Pure view-to-bitmap guide mapping and bounded crop coordinates.
  - No Android imports so geometry can be checked on the JVM.
- android/app/src/main/AndroidManifest.xml
  - Handle scanner orientation and viewport changes without cancelling capture.
- android/app/src/test/kotlin/com/motnhi/app/ScannerPreviewGeometryTest.kt
  - Meaningful rotation, aspect-ratio, and guide/crop tests.
- docs/plans/2026-10-08-scanner-camera-first-ui.md
  - Record scope, interfaces, review cases, and checks.

## Task boundaries
### Presentation
- Use the warm paper surface 0xFFFFFAF4.
- Use ink 0xFF201A18 and muted ink 0xFF746B66.
- Use border 0xFFDBD0C4.
- Use sage 0xFF3B644C and coral 0xFFDC704B.
- Load NunitoSans and SourceSerif4 from bundled Flutter assets.
- Use readable native font fallbacks if an asset is unavailable.
- Back uses an arrow, normal-case text, a rounded surface, and a ripple.
- Back has at least a 52 dp touch target.
- Guidance uses a serif heading and short sans-serif copy.
- Guidance fits a phone and has a bounded width on a tablet.
- Allow the guidance card to scroll at large font sizes.
- Keep text out of the frame's readable region.
- Use a quiet scan badge; hide it if large text cannot fit.
- Draw a dim outside-frame mask and a thin rounded guide.
- Update the guide accent when readable text is stable.
- Do not add a manual shutter or capture confirmation.

### Preview
- TextureView remains match-parent.
- Do not resize it to the camera buffer's fit-inside dimensions.
- Use uniform center-crop scaling to fill the viewport.
- Correct relative display rotation, not the sensor rotation a second time.
- Use sensor orientation only to determine native texture aspect ratio.
- Handle display rotations 0, 90, 180, and 270 degrees.
- Observe display changes, including 180-degree changes with the same size.
- Recalculate when the viewport changes.
- Reset stability when the preview layout changes.
- Guard queued OCR against old layout coordinates.
- Keep the camera permission and one-shot completion behavior.

### Capture coordinates
- The scan guide is expressed in overlay/view coordinates.
- Texture snapshots use the transformed TextureView content.
- Map the guide to bitmap coordinates with the actual snapshot dimensions.
- Use the same mapped rectangle for OCR acceptance and cropping.
- Clamp crop bounds to the bitmap and use integer floor/ceil consistently.
- Keep a snapshot of the guide for each OCR task.
- Discard a task if the guide or preview transform changes before it finishes.
- Never include the UI overlay in the captured bitmap.
- Keep final OCR and displayed JPEG in the same image coordinate system.
- Keep the native scanner result payload unchanged.

### Rotation lifecycle
- Rotation must not invoke scanner cancellation via activity recreation.
- Declare only scanner-specific orientation/size configuration handling.
- Listen to display rotation while the scanner is resumed.
- Unregister that listener on pause.
- Recompute after new layout dimensions are available.
- A rotated layout must collect new stable frames before capture.
- Pause and cancellation still release the camera.
- Backgrounding still cancels the scanner as before.

## Exact interfaces
- ScannerOverlayView receives an onBack callback.
- It exposes guideRect in overlay coordinates.
- It receives scanner-local find-page, hold-still, and preparing states.
- It reports changes to its guide rectangle through onGuideChanged.
- ScannerPreviewGeometry.textureCorners accepts viewport size, buffer size,
  sensor orientation, and display rotation in degrees.
- It returns the transformed four view-corner coordinates for Matrix.setPolyToPoly.
- Its transform assumes TextureView's camera producer already applies sensor orientation.
- ScannerPreviewGeometry.mapGuide accepts view and bitmap dimensions.
- It returns a scaled, clamped guide rectangle.
- ScannerPreviewGeometry.cropBounds returns integer x, y, width, and height.
- PageScannerActivity owns a layout generation independent of its lifecycle generation.
- Method channel, JPEG ownership, scan result keys, and AR handoff stay intact.

## Task order
1. Inspect the current scanner and the AR/theme reference files.
2. Inspect TextureView bitmap behavior in the installed SDK source.
3. Save this implementation plan.
4. Add pure preview and guide geometry with focused unit cases.
5. Build the scanner-local styled overlay.
6. Connect full-screen preview and corrected matrix calculations.
7. Connect view-to-bitmap guide mapping and stale-layout guards.
8. Handle rotation and safe-area changes.
9. Compile Android and check pure geometry.
10. Review only this task's changes against the existing scanner baseline.

## Review focus
- Portrait and landscape viewports must have no fit-inside black bands.
- A buffer with a different aspect ratio must not stretch the image.
- The transform must not add a second sensor quarter-turn.
- Display rotation 180 must update even without a size change.
- Sensor orientations 0, 90, 180, and 270 must use the correct native aspect ratio.
- The preview's central point must stay central after rotation.
- The guide must be inside the bitmap for every viewport size.
- Captured pixels must match the visible frame after center-crop.
- A state-label change must not cause an endless stability-reset cycle.
- The bottom card must not cover the readable scan guide.
- Safe-area insets must keep Back above status bars and cutouts.
- The guidance card must stay above navigation bars.
- Large text must not hide Back or prevent capture guidance from being read.
- Landscape controls must leave room for the page guide.
- Scanner rotation must not close the flow or return cancelled.
- Existing automatic capture and camera permission failure replies must still work.
- Existing uncommitted AR and backend changes must not be rewritten.

## Tests and checks
- Focused JVM geometry tests, not widget or integration tests.
- Cover all sensor/display quarter-turn combinations.
- Cover portrait phone, landscape phone, and tablet aspect ratios.
- Check uniform image scaling and full viewport coverage.
- Check center mapping and quarter-turn direction.
- Check view-to-bitmap guide mapping at different snapshot sizes.
- Check crop rounding and out-of-bounds clamping.
- Android offline compileDebugKotlin for android-arm64.
- Attempt focused JUnit tests if cached dependencies permit.
- If JUnit remains unavailable, execute assertions on compiled production geometry.
- git diff --check.
- Do not run flutter run or install the application.
- Real-device preview orientation, camera framing, and font appearance require a device check.

## Spec coverage
- Full-screen camera: match-parent preview with center-crop matrix.
- App design: paper/ink/sage/coral palette and bundled app fonts.
- Rounded Back: custom native styled touch target.
- Compact guidance: bounded rounded card and short state copy.
- Rotation fix: relative display correction, not duplicated sensor correction.
- Accurate capture area: one guide mapped to snapshot coordinates.
- Automatic scan: existing stability and capture flow.
- Responsive layout: safe areas, tablet width cap, and landscape guide placement.

## Verification results
- VERIFIED: offline Android android-arm64 compileDebugKotlin completed successfully.
- Command from android: ./gradlew --offline -Ptarget-platform=android-arm64 :app:compileDebugKotlin --console=plain
- VERIFIED: assertions on the compiled production ScannerPreviewGeometry passed 144 combinations.
- Combinations: three viewports, three buffer sizes, four sensor orientations, and four display rotations.
- Checks: viewport coverage, uniform scaling, centered content, no extra portrait sensor turn, display-turn direction.
- Additional checks: guide mapping, bounded crop rounding, and rejection of an empty crop.
- These checks used JShell against the app's compiled Kotlin classes and cached Kotlin standard library.
- BLOCKED: focused Gradle JUnit execution requires uncached junit:junit:4.13.2.
- The JUnit test source remains available for the normal test environment.
- VERIFIED: all three referenced bundled font files exist under assets/fonts.
- VERIFIED: git diff --check passed.
- VERIFIED: this repair edits only the scanner activity/manifest and adds scanner-local presentation/geometry/tests/plan.
- The earlier AR reader, backend, Flutter flow, and pubspec changes were preserved.
- Readability area is measured relative to the visible scan guide, not the whole full-screen bitmap.
- INFERRED: the sideways image was caused by applying a sensor quarter-turn to already-oriented TextureView content.
- UNKNOWN: hardware-specific camera rotation and the final on-device visual appearance.
- No device screenshot of the revised implementation was available in this session.
- Reviewer consultation was unavailable because hawkeye is not exposed by this harness.

## Read and review scope
- PageScannerActivity.kt:1-326 before edits; complete patches and updated activity reviewed after edits.
- ScannerOverlayView.kt:1-294 plus the final empty-frame guard patch.
- ScannerPreviewGeometry.kt:1-66.
- ScannerPreviewGeometryTest.kt:1-59 plus the additional buffer-size cases.
- AndroidManifest.xml:1-67 and the scanner-only configuration-change diff.
- CharacterReaderScene.kt:1-526, as the existing presentation reference.
- lib/core/theme/app_theme.dart:1-415, as the color and font reference.
- PageCaptureStability.kt:1-33, ScanPageImage.kt:1-57, and ScanAnyPageBridge.kt:1-167, for capture-coordinate compatibility.
- android/app/build.gradle.kts:1-73, for the existing toolchain and dependencies.
- Installed SDK TextureView.java:552-725, for texture transform and bitmap-copy behavior.
- Camera HAL internals and device rendering were not verified.
- Other application features and backend services were outside this repair.

## Follow-up needed
- Rebuild the Android app and visually check the revised scanner on the user's device.
- Check portrait, both landscape directions, and a 180-degree rotation.
- Confirm that readable text and the saved page match the visible scan guide.
- Confirm that switching between find-page and hold-still does not prevent automatic capture.
- Run ScannerPreviewGeometryTest when the existing JUnit dependency is available.
