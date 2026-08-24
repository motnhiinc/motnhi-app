# Scan Any Page Voice + AR Demo - Design Spec

> Physical-device demo for iPad 9th generation on iPadOS 18.6.2.
> Approved storyboard: `scan-any-page-wireframes.html`.
> This is a new OCR-first flow. It does not replace the existing known-story scan flow.

**Date:** 2026-08-14
**Status:** Approved design - ready for implementation planning

---

## 1. Goal

Prove one complete physical-device experience:

```text
scan one large-text page
  -> automatically crop and correct the page
  -> recognize English and Vietnamese text on-device
  -> let the user correct and confirm the text
  -> generate one mixed-language narration clip through the local FastAPI backend
  -> detect a horizontal surface with ARKit/RealityKit
  -> place one bundled 3D character
  -> animate the character while it reads the confirmed text
```

The success moment is: a user scans an arbitrary children's page, places a character on a table, and perceives that character as reading the page aloud.

## 2. Demo Constraints

- Target device: iPad 9th generation, iPadOS 18.6.2.
- Development: Mac with Xcode 26.2 and free Apple Personal Team signing.
- Network: iPad and Mac on the same Wi-Fi network.
- Input: one flat page at a time with large, clear English text, Vietnamese text, or both.
- Narration: OpenAI TTS called only by the local FastAPI backend.
- AR: one bundled Apple-provided sample 3D character on a detected horizontal plane.
- Distribution: local prototype only. Apple sample-asset redistribution rights must be verified or the asset replaced before TestFlight, external distribution, or publication.

Free Personal Team signing is sufficient for installing and testing on the owner's iPad. It does not support TestFlight or App Store distribution, and the development provisioning profile may require periodic re-signing.

## 3. Scope

### 3.1 In scope

- A separate `Scan any page` entry in the Flutter app.
- Native iOS document capture using AVFoundation and Vision.
- Automatic page rectangle detection, capture, crop, and perspective correction.
- Native on-device OCR using Vision with both `en-US` and `vi-VN` recognition hints.
- Editable OCR text review before any network request.
- One authenticated FastAPI TTS endpoint.
- One OpenAI TTS request for the entire confirmed text, including mixed English/Vietnamese text.
- Native RealityKit horizontal-plane detection and tap-to-place behavior.
- One bundled 3D character with idle motion and a visible speaking indicator.
- Pause/resume narration and return to scan another page.
- Clear retry states for scan, OCR, backend/TTS, audio, and AR failures.

### 3.2 Out of scope

- Replacing or modifying the existing known-story image-target scanner.
- Uploading the captured page image to the backend or OpenAI.
- Multi-page or two-page-spread capture.
- Manual language selection or automatic classification into one language.
- OCR languages other than English and Vietnamese.
- Storing OCR text, captured images, or generated audio as durable user data.
- Pre-generated or human-reviewed narration for arbitrary pages.
- Multiple characters or a character picker.
- Lip-sync, facial phonemes, or text-driven scene generation.
- Image-target AR tied to the scanned page.
- Android support.
- Offline OpenAI narration.
- TestFlight, App Store, or external beta distribution.

## 4. Product Flow

### 4.1 Entry

The app exposes a new `Scan any page` action. It is separate from the current book-first scan action so users are not asked to choose a story and the existing page-manifest contract remains unchanged.

### 4.2 Automatic page capture

Flutter asks the native document-scanner bridge to present a custom full-screen camera powered by `AVCaptureSession`.

The native scanner owns:

- camera preview;
- throttled `VNDetectRectanglesRequest` processing over preview frames;
- page-boundary visualization;
- stability and image-quality checks;
- automatic still-image capture once the page is stable;
- perspective correction with Core Image;
- capture cancellation and retry.

The demo accepts exactly one scanned page. There is no shutter action and no intermediate document-scanner confirmation screen: after the same rectangle remains stable long enough, the scanner captures one high-resolution still, corrects its perspective, and proceeds directly to OCR.

The initial demo heuristic is intentionally simple and device-tunable:

- process rectangle detection at a throttled rate rather than on every frame;
- require one dominant quadrilateral above a minimum screen-area threshold;
- require all four corners to remain within a small normalized-distance tolerance for consecutive observations;
- require acceptable focus and exposure before capture;
- reset the stability counter when the rectangle moves, disappears, or fails quality checks;
- prevent duplicate capture with a single-flight capture guard.

The exact tolerance and stable-frame count are implementation constants to tune on the target iPad with representative pages. They do not change the platform-channel contract.

### 4.3 On-device bilingual OCR

The perspective-corrected page image is passed directly to a native `VNRecognizeTextRequest` with:

```swift
recognitionLevel = .accurate
recognitionLanguages = ["en-US", "vi-VN"]
usesLanguageCorrection = true
```

The OCR bridge returns one plain-text result to Flutter. Recognized observations are ordered top-to-bottom and left-to-right before joining lines with newline characters. The bridge does not attempt to classify the page as English or Vietnamese; both hints remain enabled for every page.

The captured image exists only for the capture/OCR operation and is released after OCR completes or the flow is cancelled. It is not written into app-managed persistent storage and is never sent over the network.

### 4.4 Text review

Flutter displays the recognized text in an editable multiline field. The user can:

- correct words and Vietnamese diacritics;
- confirm with `Use this text`;
- scan again;
- enter text manually if OCR finds insufficient text.

Confirmation is required before TTS. Empty or whitespace-only text cannot be submitted. The client trims surrounding whitespace and limits confirmed text to 4,000 Unicode characters for predictable demo latency and cost.

### 4.5 Narration generation

After confirmation, Flutter sends the text to the local FastAPI backend. The app does not split mixed-language text and does not choose voices per language. The backend sends the confirmed text in one OpenAI `/v1/audio/speech` request using one configured model and one configured voice.

OpenAI voice quality across an English/Vietnamese switch is a demo validation item, not a guaranteed pronunciation contract. The editable text gate corrects OCR errors but cannot guarantee TTS pronunciation quality.

### 4.6 AR placement and playback

After audio generation succeeds, Flutter opens the native RealityKit experience. The AR view:

1. starts world tracking with horizontal-plane detection;
2. guides the user to move the iPad slowly;
3. shows a placement reticle after a horizontal plane is available;
4. places the bundled character when the user taps the reticle;
5. exposes a `Read` action only after placement;
6. starts the supplied narration when `Read` is tapped;
7. runs the character's idle animation and speaking indicator while audio is playing;
8. allows pause/resume and returning to scan another page.

The 3D figure is world-anchored to the tapped horizontal plane, not to the scanned page. Moving or removing the physical page does not affect the placed character.

## 5. Architecture

### 5.1 Flutter flow coordinator

Flutter owns the product state machine and backend interaction:

```text
idle
  -> scanning
  -> recognizing
  -> reviewingText
  -> generatingAudio
  -> placingCharacter
  -> readyToRead
  -> speaking / paused
```

Recoverable failures retain the latest safe state:

- scan/OCR failure -> return to `scanning` or manual text entry;
- TTS failure -> retain confirmed text and retry generation;
- AR initialization failure -> retain generated audio and retry AR;
- plane not found -> remain in `placingCharacter` with guidance;
- audio failure -> retain placement and retry playback.

The coordinator is independent of story IDs, child profiles, manifests, story sessions, and narration segments because arbitrary scanned pages are not curated story content.

### 5.2 Native document and OCR bridge

A small Swift bridge behind a Flutter method channel exposes one operation:

```text
scanAndRecognize() -> recognized text | cancelled | typed error
```

The bridge owns AVFoundation capture, Vision rectangle detection, Core Image perspective correction, and Vision OCR, then returns text. Flutter does not receive or transport raw image bytes. Keeping capture and OCR in one native operation makes the no-image-upload boundary explicit and avoids large image transfer over the platform channel.

Typed native errors distinguish:

- camera permission denied;
- camera/scanner unavailable;
- user cancellation;
- capture failure;
- perspective-correction failure;
- OCR failure;
- no usable text.

### 5.3 Native RealityKit bridge

A separate Swift bridge presents one full-screen native AR view:

```text
openCharacterReader(audioFilePath) -> completed | cancelled | typed error
```

The bridge owns `ARView`, `ARWorldTrackingConfiguration`, horizontal-plane detection, raycasting, model loading, placement, idle animation, playback controls, and speaking-indicator state. Flutter supplies a local audio file path, not a remote URL, so the AR screen does not own authentication or networking.

The bridge is intentionally world-plane-specific. It does not implement the existing `PageDetector` interface because arbitrary-page AR does not recognize a known image target or emit a `page_id`.

### 5.4 FastAPI TTS service

Add an authenticated endpoint:

```http
POST /v1/tts
Authorization: Bearer <device JWT>
Content-Type: application/json

{
  "text": "The little fox said, Một đêm thật đẹp."
}
```

Successful response:

```http
200 OK
Content-Type: audio/mpeg
Cache-Control: no-store
```

The backend validates:

- caller has a valid existing device bearer token;
- text is not empty after trimming;
- text is at most 4,000 Unicode characters.

The service sends one request to OpenAI and returns the resulting MP3 bytes. It does not write the text, prompt, or audio to the database or permanent storage. Normal framework access logs must not include the request body or the OpenAI key.

The backend uses the official OpenAI Python SDK as a production dependency. The OpenAI call has an explicit timeout; the request handler does not retry automatically because a retry could create duplicate billable generations after an ambiguous timeout. The user controls retries from the retained text-review state.

Backend configuration:

```text
OPENAI_API_KEY=<secret>
OPENAI_TTS_MODEL=<supported speech model>
OPENAI_TTS_VOICE=<supported voice>
```

`OPENAI_API_KEY` is required for this endpoint and remains only in the untracked backend `.env`. The model and voice are backend-controlled so the mobile client cannot request arbitrary models or voices. The restricted OpenAI project key permits `Request` only for `/v1/audio/speech`; all unrelated capabilities remain disabled.

### 5.5 Local network configuration

For device development, the app is launched with the Mac's current LAN address:

```text
--dart-define=API_BASE_URL=http://<mac-lan-ip>:8000
```

FastAPI listens on the LAN interface for the demo. The existing iOS `NSAllowsLocalNetworking` setting permits local HTTP. Existing release validation continues to require an HTTPS, non-loopback API URL, so this exception does not define a production transport policy.

The implementation must not hard-code a developer's LAN IP in source control.

## 6. Data and Privacy Boundaries

| Data | Location | Lifetime | Networked? |
|---|---|---|---|
| Captured page image | iPad native memory | Capture through OCR only | No |
| OCR text before confirmation | iPad Flutter state | Current flow | No |
| Confirmed text | iPad + FastAPI/OpenAI request | Current generation request | Yes |
| Generated MP3 | FastAPI response + iPad temporary file | Current flow/session | Yes |
| AR world map/camera frames | iPad ARKit processing | AR session | No |
| OpenAI API key | Mac backend environment | Until rotated | Never sent to iPad |

This arbitrary-page mode intentionally differs from the platform's curated-content safety model because it generates unreviewed narration from user-scanned text. Therefore:

- it is a controlled prototype, not a child-facing production feature;
- the UI must not claim that scanned content or pronunciation has been reviewed;
- no captured image is uploaded;
- no OCR text or generated audio is added to reading history or analytics;
- production release requires a separate safety, rights, privacy, and abuse review.

## 7. Audio Handling

Flutter receives `audio/mpeg`, writes it to an app temporary file, and passes that path to the RealityKit bridge. Before replacing the current narration, it deletes the previous temporary clip. It also deletes the current clip when the flow is reset or the app can no longer use it.

No fallback to on-device TTS occurs in this demo. An OpenAI/backend failure is shown truthfully with `Try again`; silently switching engines would make voice-quality testing ambiguous.

The AR experience starts narration only after character placement and an explicit `Read` tap. It does not narrate while the user is searching for a surface.

## 8. 3D Asset Contract

The demo bundles one Apple-provided sample model that can be loaded by RealityKit. The selected asset must satisfy all of these conditions before integration:

- supported by RealityKit on the target iPad;
- visible at a child-friendly table scale;
- loadable without network access;
- includes an idle animation, or can receive a simple native bob/rotation idle motion;
- has documented source and license terms in the repository;
- used only for local prototyping unless redistribution is explicitly permitted.

The speaking indicator is UI attached near the character, such as an animated sound-wave badge. It does not depend on facial blend shapes or model-specific lip-sync support.

## 9. Error Handling

| Condition | User behavior |
|---|---|
| Camera permission denied | Explain camera requirement and offer return/retry after settings change |
| Camera/scanner unavailable | Explain that this demo requires a supported physical iPad |
| Capture cancelled | Return to entry without an error alert |
| No page rectangle or unstable page | Keep scanner open with lighting, glare, distance, and corner guidance; do not auto-capture |
| OCR returns no usable text | Offer `Scan again` and `Enter text manually` |
| OCR has mistakes | Editable confirmation field |
| Confirmed text exceeds 4,000 characters | Prevent submission and ask user to shorten it |
| Mac backend unreachable | Retain confirmed text; explain same-Wi-Fi requirement; offer retry |
| Backend authentication fails | Use the existing token refresh/re-mint path, then show retry if it still fails |
| OpenAI rejects/rate-limits/times out | Backend returns a safe generic error; client retains text and offers retry |
| Invalid/non-audio backend response | Do not open AR; retain text and offer TTS retry |
| AR unsupported or initialization fails | Retain generated audio; explain requirement and offer retry/exit |
| No horizontal plane found | Keep AR open with movement and lighting guidance |
| Model fails to load | Exit AR with a specific character-load error; retain generated audio |
| Audio playback fails | Keep the placed character and offer playback retry |

Backend errors must not expose OpenAI response bodies, credentials, or internal stack traces to the app.

## 10. Testing and Validation

### 10.1 Flutter unit tests

- Flow coordinator happy path through scan, review, TTS, AR, and playback completion.
- Cancellation returns to entry without an error.
- Empty/whitespace-only and over-limit text validation.
- TTS failure retains confirmed text for retry.
- AR failure retains generated audio for retry.
- Previous temporary narration file is replaced and cleaned up.
- Existing known-story scan route remains unchanged.

### 10.2 Backend tests

- `POST /v1/tts` requires bearer authentication.
- Empty and over-limit text return validation errors without calling OpenAI.
- Mixed English/Vietnamese text is forwarded unchanged in one OpenAI request.
- Model and voice come from backend settings, not the request.
- Success returns `audio/mpeg` and `Cache-Control: no-store`.
- OpenAI authentication, rate-limit, timeout, and generic upstream failures map to safe API errors.
- No database row or permanent audio file is created.

OpenAI is mocked in automated tests; tests do not spend API credits.

### 10.3 Native iOS tests

- Rectangle stability and quality heuristic from deterministic observations.
- Single-flight auto-capture guard.
- OCR line ordering and joining logic from deterministic Vision observations.
- Typed error mapping for cancellation, no text, OCR failure, and AR/model failure.
- Platform-channel payload decoding and single-completion behavior.
- Temporary audio path is validated before opening the AR view.

### 10.4 Physical-device acceptance tests

Run manually on the iPad 9th generation with at least:

- one English large-text page;
- one Vietnamese large-text page with diacritics;
- one mixed English/Vietnamese page;
- one low-light or glare case to validate recovery;
- one corrected OCR result;
- one backend-unreachable retry;
- one successful table placement and narration.

Acceptance criteria:

- The scanner automatically captures one clear page without a manual shutter or confirmation action under normal conditions.
- OCR result is editable before networking.
- Representative large-print English and Vietnamese text is readable enough to correct rather than retype.
- The captured image never reaches the backend.
- Mixed-language confirmed text causes exactly one TTS request and one audio response.
- Audio is ready before the AR placement flow starts.
- A user can detect a table, place the character, tap `Read`, and hear narration.
- The character remains anchored while the iPad viewpoint moves.
- Idle motion and speaking indicator accurately follow playback state.
- Failed network/TTS/AR operations can be retried without rescanning the page.

No widget, end-to-end, or integration test suite is required during implementation. Physical-device QA is mandatory because AVFoundation camera capture and ARKit behavior cannot be validated meaningfully in the simulator.

## 11. Implementation Boundaries

| Unit | Responsibility | Depends on |
|---|---|---|
| Flutter scan-any-page screen/coordinator | Product states, text review, TTS call, temporary audio, native bridge calls | API client, native bridge interfaces |
| Swift scan/OCR bridge | AVFoundation camera, Vision rectangle detection/OCR, Core Image correction, no image transfer | UIKit, AVFoundation, Vision, Core Image |
| Flutter TTS client | Authenticated request and MP3 validation | Existing `ApiClient`/Dio |
| FastAPI TTS router/service | Validation, OpenAI speech request, safe audio response | Existing auth, official OpenAI Python SDK/config |
| Swift RealityKit bridge/view | Plane detection, placement, model, controls, playback visualization | ARKit, RealityKit, AVFoundation |
| Bundled Apple sample asset | One local prototype character | RealityKit |

These boundaries deliberately keep native hardware behavior in Swift and product/network state in Flutter. Neither native bridge knows about story repositories, manifests, sessions, or child-profile models.

## 12. Delivery Sequence

The lowest-risk implementation order is:

1. Verify free-signing installation and Developer Mode on the physical iPad.
2. Prove true single-page auto-capture, perspective correction, and bilingual Vision OCR through the native bridge.
3. Build Flutter text review and retry states.
4. Add and verify the authenticated local FastAPI OpenAI TTS endpoint.
5. Download audio to a temporary local file and validate mixed-language voice quality.
6. Prove RealityKit horizontal-plane placement with the selected Apple sample model.
7. Bind audio playback, idle motion, and speaking indicator.
8. Validate the complete flow on representative physical pages.

This sequence separates the three major technical risks: OCR quality, mixed-language TTS quality, and physical-device AR behavior.

## 13. Explicit Follow-ups

Before any external distribution or production use:

- replace or license-check the Apple sample character for redistribution;
- move from local HTTP to a deployed HTTPS backend;
- add rate limiting, quotas, request-cost controls, and operational monitoring to TTS;
- conduct child-safety, copyright, privacy, and abuse reviews for arbitrary scanned content;
- decide whether unreviewed arbitrary-page narration belongs in the product at all;
- define retention and deletion guarantees for any future server-side caching;
- validate more OpenAI voices against representative English, Vietnamese, and mixed-language pages;
- design Android equivalents for document capture, OCR, plane AR, and 3D asset format if cross-platform support is approved.
