# Ungated scanning and server narration — design

**Date:** 2026-10-06
**Status:** Implemented

## Goal

After the parent completes the existing profile setup, the child can scan a book page and listen without enabling separate privacy switches. The app continues to use its backend for page-image/text validation and OpenAI narration, including the server-backed TTS used by reading experiences. Existing accounts with either legacy scan permission set to false must also be able to scan and request server narration after their normal setup/policy review.

## Parent experience and disclosure

Keep parent setup, age-band/profile creation, the current-policy acknowledgement and review flow, and a clear, accurate explanation before setup finishes: scanned page images and recognized text go to the app backend and its AI validation provider; approved text goes to OpenAI for narration. In the parent Privacy & data screen, replace the cloud-narration and page-image-validation switches with informational processing copy. Retain progress tracking as an optional switch, stored-data information, reading-history deletion, and child-data deletion. Neither removed switch may imply an ability to disable processing that no longer exists. Update both English and Vietnamese copy, including the privacy notice and review where they describe optional scan permissions.

The two legacy consent values may remain temporarily in persisted data and API payloads for compatibility, but they no longer authorize or deny scanning or narration. New setup may send true for both while the old contract exists; subsequent preference updates must not accidentally make them an access gate again. Do not interpret a stored false value as a revocation of page reading. Existing consent events remain historical records; new policy acknowledgements do not record fictitious scan-specific opt-ins.

## Client and backend flow

The scan screen requires a usable child profile and authenticated API session, not effective cloud-TTS or image-validation flags. The page-validation client still checks that its operation is live and its profile ID is nonempty; it no longer checks scan-specific consent before/after network requests. Remove the missing-consent handoff and consent polling from this flow. Keep generation guards, rescan/exit cleanup of session images and temporary clips, and the one-page ready/listen/pause/replay behavior.

The backend `/v1/speakable-page/validate` and `/audio` endpoints no longer enforce either legacy scan choice. They still authenticate the user, verify profile ownership and server-owned age band, validate bounded image/OCR input, fail closed on uncertain or unsuitable content, and require a signed approval bound to user/profile/exact text before audio generation. `/v1/tts` likewise ceases to require the legacy cloud choice, retaining authentication, input validation, OpenAI generation, and existing upstream-error behavior. For other reading flows that select between cloud and device narration based on the legacy flag, select cloud by default so an old off value does not silently force device TTS; retain an existing device fallback for operational cloud failures only where that experience already has one. The scan-page proof-gated audio path stays server-only.

Keep the baseline setup/policy-review gate for profile creation and unrelated progress/storage controls. Bump the policy version for the changed processing disclosure; on re-review, preserve the parent's existing progress-tracking choice unless they change it. A missing or inaccessible profile, invalid proof, rejected page, or service outage still prevents scanned-page playback. Lack of a scan-specific privacy preference never produces a setup handoff or 403. The backend should not persist scanned images, OCR text, verdicts, or generated page audio in app storage; temporary local media is cleared on exit/rescan as before.

## Rollout and verification

Ship backend acceptance of legacy false/missing scan choices before or alongside the client removal so an updated UI never promises playback that the server denies. Keep the existing API fields during compatibility rollout, and remove unused client-only effective-consent plumbing where safe without breaking unrelated privacy features.

Verify onboarding and policy review still lead to a valid profile; both brand-new and existing accounts with false legacy flags can validate a page, obtain a proof, and generate server audio; generic TTS reaches the OpenAI service without those flags; profile ownership, blocked content, tampered/expired proof, invalid input, and upstream outages still fail correctly. Confirm the two switches are absent from parent settings and disclosure text accurately explains third-party processing in both locales. Preserve the current worktree's in-progress onboarding and scan edits rather than overwriting them wholesale.
