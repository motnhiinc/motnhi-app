# Scan: AR beside Listen

## Approved scope
- User selected AR beside Listen after scanning.
- User selected the existing story AR reader.
- Use the saved character selection.
- Read every validated scanned line in order.
- Reuse already generated narration.
- Keep Listen available after returning from AR.

## File map
- `lib/features/scan_any_page/scan_any_page_screen.dart`
  - Add support probing.
  - Add the AR action.
  - Add launch and return handling.
  - Attach adapter cleanup to screen resource disposal.
- `lib/features/scan_any_page/scanned_page_ar_audio.dart`
  - Adapt ordered scan clips to one AR narration page.
  - Own temporary AR copies.
  - Wait for preparation before cleanup.
- `test/scanned_page_ar_audio_test.dart`
  - Test ordered audio conversion.
  - Test filename compatibility.
  - Test preparation failure and cleanup.
  - Test cleanup during preparation.
- `docs/scan-listen-ar-plan.md`
  - Record approved scope and implementation checks.

## Existing interfaces
- `storyReaderProvider` supplies `StoryReader`.
- `StoryReader.isSupported()` returns capability information.
- `StoryReader.open()` receives narration pages and a character.
- `ArNarrationPage` carries page id, page number, and ordered paths.
- `selectedArCharacterProvider` supplies the saved character.
- `childProfileProvider` supplies the parent AR setting.
- `PageValidationClient` supplies ordered MP3 files.
- `LineAudioPlayer` owns Listen playback.
- `liveResourceDisposersProvider` registers screen cleanup.
- Native readers share a single presentation slot.

## Adapter interface
- Class: `ScannedPageArAudio`.
- Constructor accepts an optional temporary-directory supplier.
- Android uses `getTemporaryDirectory`; iOS uses `Directory.systemTemp`.
- Tests inject a local temporary root.
- `prepare(List<File> clips)` returns `Future<ArNarrationPage>`.
- `dispose()` returns `Future<void>`.
- Adapter owns only its temporary AR copies.
- Source clips remain owned by the validation client.
- Adapter never moves or edits a source clip.
- One adapter belongs to one scan generation.
- Successful preparation is reused for AR retries.
- Preparation failure permits another attempt.
- Disposal prevents new preparation.
- Disposal waits for active preparation.
- Disposal removes the owned directory.

## Audio contract
- Represent a scan as one narration page.
- Page id is `scanned-page`.
- Page number is 1.
- Preserve the supplied clip order.
- Use the existing `arSegmentFileName` helper.
- Use story id `scan` for adapter filenames.
- Use zero-based segment order.
- Use MP3 extension because scan audio is MP3.
- Reject empty clip lists.
- Reject more than 10000 clips.
- The native segment-order pattern allows four digits.
- Reject missing or empty source files.
- Create an isolated temporary subdirectory per adapter run.
- Android requires paths below the app cache directory.
- iOS requires paths below the app temporary directory.
- Match the native root; path_provider's iOS cache root is not accepted.
- Copy each source before exposing any narration page.
- Native receives the full bundle only after copying completes.
- Partial preparation never opens AR.
- Remove partial copies after failure.
- A cancellation check runs after each asynchronous operation.

## Screen state
- Store one adapter with the current scan.
- Track whether the device supports the reader.
- Track whether an AR launch is busy.
- Probe native support once on screen initialization.
- Ignore capability responses after screen disposal.
- Require a loaded profile with AR enabled.
- Recheck permission before launch.
- Require a ready scanned page.
- Require generated audio clips.
- Guard repeated AR taps.
- Capture the current scan generation before asynchronous work.
- Check mounted and generation after asynchronous work.
- Mark AR busy before preparation starts.
- Disable Listen and scan actions while AR is busy.
- Pause Listen before opening the native reader.
- Launch with the saved character.
- Start the one-page reader at index zero.
- Do not generate additional speech.
- A completed reader returns to the scan page.
- A cancelled reader returns to the scan page.
- Return the Flutter controls to the ready state.
- Show a localized error if launch fails.
- Keep audio available after an AR failure.
- Clear busy state in a finally block.

## Layout
- Place Listen and See in AR in one row.
- Give each visible action equal width.
- Use the existing localized `seeInAr` string.
- Use an AR icon for the new action.
- Keep the existing Listen action style.
- Hide AR when parent permission is disabled.
- Hide AR when native support is unavailable.
- Keep Listen full width when AR is hidden.
- Keep existing pause/resume/replay controls.
- Keep existing Scan another page action.

## Cleanup order
- Increment generation when resources are disposed.
- Dispose the AR adapter before source audio cleanup.
- Await any adapter preparation before removing copies.
- Dispose the validation client.
- Dispose the line audio player.
- Unregister the screen callback on screen disposal.
- Dispose the old adapter before a new scan.
- Create a fresh adapter for the new scan.
- Do not delete user-created files.

## Task order
1. Verify native filename and containment contracts.
2. Save this plan.
3. Implement the adapter.
4. Add meaningful adapter unit tests.
5. Add capability probing and the screen launch handler.
6. Add the side-by-side ready-state actions.
7. Run targeted unit tests.
8. Run targeted static analysis.
9. Review the complete task diff.

## Review focus
- Source clips named `000.mp3` are not native-compatible.
- Source paths must never be passed directly to native AR.
- Multiple lines must not collapse to the first line.
- Listen must not overlap native audio.
- Back navigation may occur during copying.
- Child-data cleanup may occur during copying.
- AR retry must not use partially copied audio.
- A new scan must not reuse the previous page's narration.
- Permission may change after initial screen build.
- Unsupported devices must keep Listen usable.

## Verification and coverage
- Unit test ordered contents and native-compatible filenames.
- Unit test source preservation and owned-file cleanup.
- Unit test invalid inputs and missing clips.
- Unit test cleanup while preparation is pending.
- Run existing native story-reader unit tests.
- Analyze modified Dart files.
- Review row placement and busy-state guards in the diff.
- Physical-device AR validation remains a manual follow-up.

## Completed checks
- Targeted adapter and native reader unit tests: 16 passed.
- Static analysis of the three task Dart files: no issues.
- `git diff --check`: passed.
- Reviewed the complete modified screen and audio adapter.
- Reviewed native filename/root constraints and saved-character provider.
- Physical-device launch and visual layout were not verified.
- The `hawkeye` reviewer is unavailable in this session.
