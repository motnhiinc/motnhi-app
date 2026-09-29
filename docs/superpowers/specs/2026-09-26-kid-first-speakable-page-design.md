# Kid-first speakable page — design

**Date:** 2026-09-26
**Status:** Approved product direction; implementation pending
**Visual reference:** [Paper app screens and flow](https://app.paper.design/file/01M3DXY6WQN072R1SMD0GH5Z7N/p-1-0)

## Goal and scope

After a parent has completed setup, a child opening the app can hear a scanned book page in **two taps**: **Scan a page**, then **Listen**. The camera captures automatically; image-to-text checking, age-suitability screening, and narration preparation require no child action. The photographed page remains visible while a gold highlight follows the spoken line. A failed or uncertain check never enables playback.

This replaces the child-facing `Scan any page` journey (currently home → scan entry → OCR editor → TTS → AR entry → surface placement → Read). The existing curated story library and its player remain accessible; AR is not required for arbitrary-page listening. The first release is a single page per session on the supported physical iPad, with English, Vietnamese, and mixed-language text as in the existing scanner. It does not add word-level synchronization, history for arbitrary pages, Android capture, or an AI-written rewrite of a scanned page.

## Child journey

1. **Home:** Promote **Scan a page** to the main child action. Keep the story library and gated parent area available. If setup/consent is missing, the action leads to a simple **Ask a grown-up to set up page reading** state, whose setup action goes through the parental gate. Never ask the child to grant image-upload permission.
2. **Scan:** Open the existing automatic one-page camera scanner. Show a clear page frame and steady/lighting guidance. Under normal conditions there is no shutter or confirmation tap. Cancellation returns without an error.
3. **Prepare:** Show **Making your page ready** with a neutral page silhouette and progress indication. Do not display unapproved OCR text or enable Listen. Capture, validation, and preparing all audio occur before the ready state.
4. **Ready:** Display the corrected photograph of the same page, **Page ready to listen**, a large **Listen** action, and **Scan another page**. Do not autoplay.
5. **Listening:** Play approved lines sequentially. Highlight the corresponding printed line region as each clip starts; hold it while paused; advance only when that clip finishes. Provide Pause/Resume, replay from the start, and scan another page. On completion retain the page with replay available.
6. **Blocked:** If text and image disagree, content is unsuitable for the child's age band, recognition is insufficient, or validation is uncertain, show only **We can't read this one right now. Choose a different page to scan** and **Scan another page**. Do not show the rejected image/text or a Listen action. A technical/network failure may offer retry of the same scan while locally retained, but must keep playback disabled and must not be described as an approved page.

The two-tap count starts on the child home with effective parent consent, camera permission, and backend connectivity already available. It is an interaction count, not a guaranteed time-to-sound improvement.

## Capture and page geometry

Extend the iOS scan bridge to return a session-scoped corrected-page image and an ordered list of OCR lines, each with text and a normalized bounding box in the **corrected image's coordinates**. The existing Vision observations already have bounding boxes but currently return only a joined string and discard the image. Preserve the same ordering for display, validation, and narration. Encode a corrected JPEG no larger than 8 MiB or 3,000 pixels on its longest edge while preserving legibility; reject rather than silently sending an unreadable image. Accept at most 40 lines and 4,000 Unicode characters of text for one page. Flutter holds the image in session-local temporary storage/memory, never in the story library or camera roll.

The reader renders the image with aspect-fit geometry and maps normalized OCR boxes through that same fitted image rectangle. A translucent gold rectangle/underline highlights one printed line without replacing the photograph with reflowed text. If boxes are missing, invalid, out of range, or cannot be associated one-to-one with approved narration lines, block the page rather than showing misleading karaoke alignment.

## Validation and consent boundary

Add a distinct, initially-off **cloud page-image validation** parent choice in onboarding, policy review, and gated privacy settings. Explain that the corrected page image and recognized text are sent to the app backend and its AI validation provider; cloud narration remains a separate existing choice. Page reading requires **both** effective choices. Version the privacy policy so existing parents review the new image-sharing purpose; persist consent events and allow revocation. Both the client and backend derive effective permission from current server state; stale cached permission cannot authorize upload. Recheck fresh consent before Listen, on app foreground/resume, and periodically during playback (at most 15 seconds between checks). On observed revocation or an unavailable consent check, stop playback, remove local image/audio, invalidate the pending flow, and require fresh setup before another scan. The backend rechecks consent for each validation/narration request; remote revocation cannot be observed instantaneously while the app is offline.

The authenticated backend validation endpoint receives one compressed image, ordered OCR lines/boxes, and the selected child-profile ID. It resolves the profile's age band **server-side** and verifies ownership, current policy, effective image-validation consent, and effective cloud-narration consent. Check JPEG MIME/signature, dimensions (long edge at most 3,000 pixels), byte size (at most 8 MiB), nonempty text, line count (at most 40), total 4,000-character limit, and normalized boxes before calling the AI provider. The provider returns a strict structured verdict for (a) whether the OCR lines match the image closely enough to read exactly as supplied and (b) suitability for the profile's existing age band. The age policy rejects sexual content, graphic violence, self-harm instructions, and other material judged unsuitable for that band. No rewritten/generated text is substituted. Any disagreement, uncertain/invalid verdict, timeout, provider error, or rejected content fails closed. The UI receives only an approved/blocked/temporary-error result and no detailed harmful-content description.

An approval is bound to this authenticated user, profile, **exact ordered text lines**, and a ten-minute expiry by a signed, tamper-evident proof. The scanned-page narration endpoint requires that proof, rechecks current consent and profile ownership, and verifies the lines against it before generating audio. This prevents a scan-flow client from swapping approved text for unreviewed text between validation and narration. The existing generic `/v1/tts` remains for its other authorized uses; the child scan flow exclusively uses the proof-gated endpoint.

The backend neither persists the image, OCR text, verdict, nor audio in application storage nor includes them in access/error logs. Do not upload until parent consent is effective. Delete local session image and temporary clips on rescan, exit, disposal, or revocation; handle stale async completions so they cannot restore ready/playable state. The parent disclosure must accurately describe third-party processing; app-side nonretention is not a claim about provider retention.

## Narration and state ownership

Generate **one clip per approved OCR line**, in order, with the configured backend voice. The proof-gated endpoint returns a bounded ordered audio bundle; it succeeds only if every line has valid audio. A partial bundle never produces a ready page. The Flutter scan coordinator owns `idle → scanning → preparing → ready → playing/paused/completed`, with blocked and recoverable technical-error branches. A dedicated line-player owns clip playback, current-line index, pause/resume, replay, and cleanup. The page renderer depends on the current-line index but does not manage networking or playback. Preserve the existing single-flight/generation guards when rescanning or leaving while validation/TTS is in flight.

The parent setup/privacy surface owns the new opt-in. The Swift scanner owns capture, correction, OCR, and coordinates. The authenticated backend owns consent enforcement, profile-age lookup, image+OCR validation, approval proof, and gated audio generation. The UI must not treat a successful OCR result, an old approval, or a locally generated clip as sufficient to show Listen.

## Recovery and verification

- Camera permission/quality failures retain guided rescan behavior; cancel is quiet.
- Missing consent routes through the parental gate. No upload is attempted while consent is unavailable.
- Invalid/uncertain/unsuitable validation is blocked without a child bypass; technical failures can retry while the captured session remains valid and consent remains effective.
- Audio generation failure retains the approved session only while the proof remains valid; retry through the gated endpoint or revalidate after expiry. Never show Listen with incomplete audio.
- Physical-device checks cover English, Vietnamese diacritics, mixed language, glare/low light, rotated pages, inaccurate OCR, age-inappropriate/borderline content, consent off/revoked, validation outage, TTS outage, rapid rescan/exit, and app interruption.
- Automated tests cover effective-consent enforcement, server-owned age band, fail-closed verdict parsing, proof binding/expiry/tamper, zero TTS calls on rejection, ordered clip bundling, coordinate transforms, playback/highlight transitions, cleanup, and stale-operation suppression. Use mocked AI/TTS in automated tests. Measure actual time-to-first-sound separately from the two-tap count on the target iPad.

The AI gate reduces the chance of unsuitable narration but cannot guarantee that every page is safe. The UI must not make that guarantee.
