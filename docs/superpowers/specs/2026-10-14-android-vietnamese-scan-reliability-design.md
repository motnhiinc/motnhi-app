# Android Vietnamese scan reliability and latency — design

**Date:** 2026-10-14

**Status:** Proposed implementation spec; physical-device baseline pending

**Primary market:** Vietnamese-speaking families

**Primary flow:** Home → Scan a page → Listen on Android

## 1. Goal

Make the core reading flow reliably capture Vietnamese book text, preserve its diacritics, and produce natural Vietnamese narration with a shorter wait. Recover from transient failures without asking users to photograph an already-readable page again.

This spec builds on the kid-first speakable-page design (2026-09-26) and the implemented ungated scan/server-narration design (2026-10-06). The latter takes precedence for setup and processing authorization. Do not restore the removed scan-specific consent switches. Existing profile ownership, page validation, exact-text approval, and session cleanup remain part of the flow.

The Android fixes are the delivery target. Shared Flutter/backend changes must remain compatible with other clients. iOS camera changes are outside this slice.

## 2. Current implementation and evidence

| Area | Current behavior | Consequence |
|---|---|---|
| Capture | `ScanAnyPageBridge.kt` launches Google's managed document scanner in full mode | Our app does not directly control its autofocus, exposure, or shutter |
| Image processing | `ScanPageImage.kt` downsamples by powers of two until the longest edge is ≤3,000 pixels | A 4,000-pixel capture becomes about 2,000 pixels, sacrificing potential text detail |
| Recognition | Bundled ML Kit Latin recognition runs on the orientation-corrected bitmap | There is no iOS-style English-first language list to reorder on Android |
| Quality | No app-owned sharpness assessment; line confidence/language metadata is discarded | Poor recognition is discovered late, often by cloud validation |
| Limits | Empty output, >40 lines, and >4,000 characters all produce `no_text` | Successful recognition of an oversized page looks like recognition failure |
| Validation | Image/text mismatch, uncertainty, and unsuitable content share `blocked` | Recovery cannot distinguish retryable recognition problems from rejected content |
| Audio | Backend synthesizes every printed line serially and returns a complete ZIP | Wait time increases with line count; one upstream failure loses the request |
| Voice | Cloud speech receives text but no explicit content-language instructions | Vietnamese pronunciation is not explicitly configured or independently evaluated |
| Recovery | Active screen restarts capture for most failures | Validation/audio outages force unnecessary retakes |

The active route uses `ScanAnyPageScreen` and `PageValidationClient`. The older `ScanAnyPageController` is not the state owner for this route. Implement state changes in the active flow rather than fixing only the old controller.

These are code findings, not measured root causes on the co-founder's device. Record a baseline before attributing the observed delay to OCR.

## 3. Delivery scope

### Release A — correctness, speed, recovery

1. Stage-level diagnostics and an Android benchmark corpus.
2. Precise, memory-bounded image resizing that retains Vietnamese text detail.
3. Explicit content language through scan-page validation and cloud narration.
4. Bounded parallel line synthesis, retaining the existing ordered ZIP contract.
5. Typed failure reasons and retry of the failed stage using session-local data.
6. Post-capture quality scoring, initially observational and then calibrated for retake guidance.

### Follow-up B — gated by Release A measurements

- Selective cloud OCR fallback for readable images that native OCR cannot transcribe reliably.
- Sentence-based progressive playback with a new endpoint/player contract.
- Vietnamese voice/provider comparison if explicit instructions do not meet listening acceptance.

A custom CameraX scanner is a separate decision only if the managed capture stage remains the dominant source of failures. Release A retains Google document scanning and bundled ML Kit OCR.

## 4. Measurement and diagnostics

Create a random, session-scoped scan attempt ID. Use monotonic clocks for durations and propagate the ID to backend requests; assign a new operation ID for each retry. Do not use a child identifier as the diagnostic correlation ID.

Record these stages separately:

- Scanner intent acquisition and managed scanner round trip. The latter includes user positioning/review time; do not label it OCR latency.
- Image decode, orientation normalization, resize, JPEG encoding, and local OCR.
- Validation request round trip and server/provider validation duration.
- Audio request round trip, server queue wait, individual synthesis durations, bundle creation, extraction, and player loading.
- Capture-return → Listen enabled, and Listen tap → first audible playback. Record first sound from playback instrumentation rather than the completion of `play()`.

Diagnostic fields: app/build version, Android/device model, cold/warm run, network category, image dimensions/byte count, line/character counts, quality-score version, stage, reason code, retry number, and elapsed time. Never log image bytes, OCR text, audio, approval proofs, or provider response bodies. Keep provider errors mapped to bounded codes.

Measure first-run scanner availability separately from warm scans. The OCR dependency is bundled; do not assume every first-use delay is an OCR model download. Give scanner initialization its own visible loading state and bounded failure handling.

## 5. Android image and recognition pipeline

### 5.1 Resize and coordinate contract

Use an orientation-corrected bitmap with longest edge `min(sourceLongestEdge, 3000)`; never upscale a smaller capture. Choose a sampled decode that retains enough pixels for the final size, then perform one filtered resize to the exact target. Bound intermediate allocation and handle unsupported/oversized source images without crashing. Recycle superseded bitmaps promptly.

Examples: 4,000 → 3,000; 6,000 → 3,000; 2,048 → 2,048 pixels on the longest edge. Preserve aspect ratio within rounding error, EXIF rotation, and mirrored orientations.

OCR, normalized line boxes, returned width/height, and encoded JPEG must describe the same final bitmap. Keep the 3,000-pixel/8-MiB output limits. JPEG encoding quality may be reduced within the existing byte budget; an encode failure must not masquerade as `no_text`.

ML Kit reads the bitmap, not the encoded JPEG. Evaluate OCR detail loss and JPEG-related validation loss independently. Benchmark peak memory as well as accuracy because preserving more pixels increases allocation relative to the current decoder.

### 5.2 Quality assessment

Compute normalized sharpness and text-size signals on the processed image, preferentially inside detected text regions. A whole-page edge score alone is insufficient: illustrations can be sharp while text is unreadable. Track overexposure/glare signals as supporting evidence, not an uncalibrated hard rejection.

Start in diagnostic-only mode. Label readable/unreadable images in the device corpus and choose versioned thresholds using a held-out set. A quality gate may request a retake only after calibration demonstrates an acceptably low false-retake rate. Low-confidence OCR alone must not be interpreted as physical blur.

Preserve recognition confidence and language metadata where the pinned ML Kit API exposes them. Missing metadata is unknown, not zero confidence. Do not invent a Vietnamese-language hint API for the Latin recognizer.

Keep the managed scanner UI. Our quality guidance appears after its result; live focus control and custom live guidance require a different camera implementation. Do not automatically relaunch the camera in an endless retry loop.

### 5.3 Result and error contract

Add optional, versioned quality metadata to the native result; old payloads without it remain readable by Flutter. Return distinct errors for `no_text`, `page_too_long`, `image_decode_failed`, `image_encode_failed`, `ocr_failed`, and `capture_failed`. Use `image_quality_low` only when an enforced, calibrated quality gate identifies an unreadable capture. Preserve quiet cancellation.

Apply the existing limits consistently: at most 40 lines and 4,000 Unicode code points. Do not silently truncate a page. Review reading order with multi-column and illustrated layouts; the existing fixed row tolerance is provisional and can reorder nearby lines. Retune only with fixture evidence.

## 6. Vietnamese language and narration

### 6.1 Content language

Introduce `content_language` with explicit values `vi` and `en` for this release. Android defaults new scan sessions to `vi`; preserve a parent's explicit alternative. UI locale and device locale do not override the selected content language. Mixed-language pages use the selected dominant language and are included in listening evaluation; automatic sentence-level switching is follow-up work.

Carry content language through the Flutter session, validation request, approval proof, and audio request. An app locale change must not silently change narration mid-session.

### 6.2 Cloud speech

Extend the TTS service interface to accept optional content language. For explicit Vietnamese requests, use the configured instruction-capable speech model with instructions to read the supplied Vietnamese text faithfully, use natural Vietnamese pronunciation and child-friendly pacing, and not translate or add words. English requests receive corresponding English guidance.

Retain the current configured voice as the initial baseline. Compare corrected configuration against current output with native Vietnamese listeners before changing voice/provider. Configuration alone is not evidence that pronunciation is fixed. Declare compatibility with the deployed speech model: unsupported instruction configuration must fail visibly in deployment verification rather than silently dropping language intent.

Test two inputs separately: ground-truth Vietnamese text and OCR-derived text. This isolates speech-quality failures from recognition failures. Preserve diacritics exactly; normalize Unicode to NFC once before validation/proof creation, then use those exact normalized strings for audio. Do not restore missing accents heuristically or rewrite story content.

The scan-page path stays cloud/proof-gated. Explicit Vietnamese device-voice selection in AR/authored-story fallback is an adjacent follow-up, not the implementation of this scan fix.

## 7. Backward-compatible API changes

### Validation

Keep `POST /v1/speakable-page/validate`. Add optional `content_language`; omission preserves legacy behavior for old clients rather than guessing Vietnamese from device locale.

Keep the existing response statuses. Add a machine-readable `reason` to blocked responses, limited to `text_mismatch`, `recognition_uncertain`, or `content_unsuitable`. Provider transport/parse failures remain temporary errors, not content judgments. Refine the validator's internal structured result sufficiently to distinguish text certainty from content suitability certainty. If suitability is uncertain or rejected, never classify the page as merely a correctable text mismatch; return the conservative blocked state without harmful-content details.

Do not loosen matching to make bad OCR pass. Whitespace/Unicode canonicalization must be deterministic before approval; semantic changes require new validation.

### Approval and audio

Keep `POST /v1/speakable-page/audio` and the ordered ZIP response. Add optional `content_language` to the request. New proofs include a version and the explicit language when supplied, alongside the existing user/profile/exact ordered-text digest and expiry. Reject attempts to change a proof's language during audio generation.

During rollout, legacy requests/proofs without language continue on the legacy behavior. An explicit-language audio request requires a matching language-bound proof; it must not borrow an old unbound proof. Return a typed proof-expired reason separately from invalid/tampered proof so the client knows when revalidation is appropriate. Never trust an unverified expired token to authorize audio.

Add additive reason codes for temporary validation/audio failures, including provider timeout and capacity/rate limiting. Preserve bounded response bodies without echoing OCR content.

## 8. Bounded parallel audio generation

Run independent line synthesis calls with configurable per-page concurrency, initially 3 for benchmarking. Preserve output order by original index, regardless of completion order. Write the ZIP on one thread after successful results; do not share a mutable `ZipFile` among workers.

Use both per-page and per-process upstream concurrency limits. Configure deployment-wide capacity with the worker/replica count; a process-local semaphore is not a global provider rate limiter. Bound queue wait and total page-generation time. Benchmark values before promoting them; do not allow every 40-line request to create 40 workers.

Retain individual 2-MiB clip and 32-MiB bundle limits. Enforce aggregate memory bounds while collecting results, not only while writing the final archive. No persistent server cache is introduced.

For Release A, a partial bundle never enables Listen. On failure, stop scheduling new work, cancel pending jobs, let unavoidable in-flight provider calls settle under their timeouts, and discard partial output. Use a narrowly bounded retry for transient upstream errors only, within the page deadline. Never retry invalid text, proof failures, or content rejection as TTS work.

Suggested initial configurable budgets for measurement: 15 seconds for validation provider work, 30 seconds for total page audio generation including queue/retry time, and a client receive budget slightly longer than the server deadline. Set explicit connect/send/receive timeouts; tune using real network and page-length data rather than hiding long waits with unlimited timeouts.

## 9. Session state and recovery UX

Move orchestration out of screen-local ad hoc transitions into a testable coordinator for the active scan route. It owns the captured page, exact normalized lines, content language, approval, temporary clips, cancellation, and operation generation. The screen renders state and dispatches actions.

States: `scanning → recognizing → validating → preparingAudio → ready → playing/paused/completed`, plus typed recoverable failure and blocked states. Until the native bridge exposes progress, `recognizing` may be internal telemetry rather than a separate visible phase; do not fabricate live progress events.

| Failure | Primary action | Retained session data |
|---|---|---|
| Unreadable capture/no text | Retake with specific guidance | No playable media |
| Oversized page | Explain supported amount; scan a smaller section | No playable media |
| Validation timeout/network failure | Retry validation | Image, lines, language |
| Text mismatch/recognition uncertainty | Retake in Release A | No approved/playable state |
| Unsuitable or suitability-uncertain page | Choose another page | Clear rejected page/media |
| Audio timeout/network failure | Retry audio | Approved page and proof while valid |
| Expired proof | Revalidate same capture, then generate audio | Image, exact lines, language |
| Invalid/tampered proof | Clear approval; surface typed failure | Never proceed directly to audio |

Keep capture → validation → narration progress copy distinct, without fake percentages. Before approval, retain the existing neutral illustration. After approval, show the captured page while audio prepares, with Listen disabled. This avoids contradicting the existing rejected-page display behavior.

Vietnamese guidance must explain the actual next action. Suggested copy: `Ảnh chưa rõ. Giữ máy yên và chụp lại nhé.` for confirmed poor quality; `Đang nhận diện chữ…`; `Đang chuẩn bị giọng đọc…`; and a retry message for service/network failure. Do not label every error a connection problem. Retain English localization parity.

Use a cancellation token for client HTTP operations and generation guards for every completion. A new scan, exit, disposal, or child-data cleanup cancels pending work and clears session image/temporary media. A stale response cannot restore ready state or recreate retained files. Retrying a stage reuses the current capture rather than calling the native scanner again.

`just_audio` play completion must not be used as the signal to enter `playing`; drive UI transitions from player state/stream events. Verify pause becomes available as soon as playback starts, not after the page finishes.

## 10. Follow-up designs and decision gates

### Selective cloud OCR

Proceed only if the corpus shows unacceptable diacritic/text accuracy after resizing/capture improvements. Benchmark native OCR against at least one Vietnamese-capable cloud candidate using the same images. Compare character error rate, reading order/boxes, latency, and cost per successfully read page.

Fallback eligibility: readable image plus uncertain/mismatched native transcription. Blurry/unreadable content requests a retake rather than speculative reconstruction. A content-unsuitable verdict does not trigger OCR fallback.

Any fallback must return image-grounded text and usable geometry, preserve the image coordinate contract, and validate the replacement text before issuing a new proof. Never reuse approval for the old strings. Cloud-provider selection and endpoint details require a follow-up spec after the benchmark; Release A does not introduce an untested provider.

### Progressive sentence audio

Proceed if audio remains the dominant post-capture delay. Replace printed-line units with approved sentence/short-paragraph units, each mapped to one or more source line boxes. Playback remains user-started after page approval.

A new versioned contract must support initial playable audio, ordered later chunks, backpressure, cancellation, partial-generation errors, and replay. It must bind segment text to the approved page and avoid arbitrary-text synthesis via segment requests. The existing complete-ZIP endpoint cannot provide progressive playback.

Sentence clips cannot promise exact line timing without alignment data. Either highlight the corresponding group of lines or supply tested timestamps. Define that UX and authorization contract before implementation.

## 11. Acceptance and verification

### Corpus and physical-device runs

Start with at least 50 transcribed Vietnamese pages covering diacritics, small fonts, colored/illustrated backgrounds, glossy paper, curved bindings, rotated captures, and multi-column layouts. Include English and mixed-language regression pages. Keep a held-out subset for threshold evaluation. Use controlled fixtures for automated work and separately authorized test captures for physical evaluation.

Test the actual co-founder's Android model plus a representative lower/mid-range GMS device. Earlier Android notes list Pixel 6a and Nothing Phone 3a; confirm current availability rather than assuming those are today's test devices. Compare baseline and candidate release/profile builds with the same page/device/network conditions, including cold and warm scans, Wi-Fi and mobile data, repeated scanning, cancellation, background/resume, and network loss.

### Proposed pilot targets

These are release goals, not existing measurements. Record baseline values and revise explicitly if the corpus/device evidence makes a target unrealistic.

- ≥95% first-attempt completion on readable, supported-length Vietnamese pages in normal lighting.
- ≤1% Vietnamese character error rate on the normal-condition held-out corpus after NFC normalization; report diacritic errors separately.
- ≤5% false-retake rate among readable held-out captures after enabling quality enforcement.
- ≥30% reduction in p95 capture-return → Listen-ready time on multi-line pages versus baseline, with no reliability regression.
- Listen tap → first sound p95 ≤500 ms when clips are already local.
- Native Vietnamese listeners rate ground-truth-text narration at least 4/5 on pronunciation/naturalness on average; record wrong-language/accent failures explicitly.
- No extra camera launch when retrying validation/audio on a retained valid capture; no stale playback or crashes during lifecycle stress runs.

Report slow/error cases by stage and page length. Do not mix user positioning time into recognizer timing or exclude failed attempts from the success-rate denominator.

### Automated checks for implementation

- Android fixtures: exact resizing, EXIF rotate/mirror, no upscaling, output bounds, memory/error paths, preserved line geometry, Unicode counts, distinct overflow/no-text failures, and reading-order examples.
- Flutter coordinator: retry only the failed stage, expiry revalidation, correct language propagation, disabled Listen until approved/full audio, cancellation, stale response/file cleanup, and playback-state transitions.
- Backend: language instructions; old-client compatibility; language/text/profile proof binding; expiry/tamper rejection; stable ZIP ordering with deliberately out-of-order completions; concurrency ceilings; queue/deadline handling; aggregate byte limits; failure cleanup; no TTS calls on rejected pages.
- Integration: full Android scan → validation → ordered narration with mocked services for deterministic failures; physical-device corpus runs for actual OCR, camera quality and voice quality.

Run targeted Android unit tests, Flutter analysis/coordinator tests, and backend endpoint/service tests for each implementation slice. Use the Marionette Flutter verification workflow when exercising changed app behavior on a running device. Unit tests do not substitute for the physical camera/listening acceptance runs.

## 12. Implementation map and rollout

| Slice | Primary files/areas | Completion evidence |
|---|---|---|
| A1: baseline | Android bridge/image pipeline; Flutter scan coordinator; backend routes/services | Per-stage timings and reproducible device baseline |
| A2: image fidelity | `android/.../scananypage/ScanPageImage.kt`, `ScanAnyPageBridge.kt`, `ReadingOrderSorter.kt`; `scanned_page.dart` | Fixture accuracy, dimensions, geometry and memory checks |
| A3: Vietnamese speech | `page_validation_client.dart`; backend schemas, `page_approval.py`, `tts.py`, `config.py` | Compatible language-bound proof flow and native-speaker comparison |
| A4: speed | `backend/app/routers/speakable_page.py` and extracted audio orchestration service | Bounded concurrency, deterministic ZIP and measured latency reduction |
| A5: recovery | Active scan coordinator/screen, validation client, line player, localization | Stage retries, typed UX, lifecycle/device checks |
| A6: quality enforcement | Android quality scoring and scan failure UI | Held-out threshold results before switching from observation to enforcement |

Deploy additive backend language/reason/proof support before the updated Android client. Preserve legacy requests during the transition. Make parallelism, quality enforcement and Vietnamese instruction configuration independently configurable so each can be compared or rolled back without disabling scanning.

Roll out to the internal Android cohort first. Compare both success rate and stage latency to baseline before expanding. Release A is complete only when the functional checks and physical-device results are recorded; cloud OCR fallback and progressive playback are separate follow-up deliverables.
