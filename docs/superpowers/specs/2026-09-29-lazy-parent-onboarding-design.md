# Quick-start parent onboarding

**Date:** 2026-09-29
**Status:** Implemented

## Goal

Let a parent begin reading after one required consent action, without asking them to configure optional preferences or enter child details. Keep defaults visible and reversible in Parent settings.

## First-run screen

- Show a short welcome heading and one sentence: reading is ready with sensible defaults, and preferences can be changed later in Parent settings.
- Show one compact, plain-language required disclosure: creating a child profile stores its age range and story language in the app cloud; stories the family chooses to save are also stored. No nickname is collected during setup. Include a clearly labeled link to the full localized privacy notice.
- Show an unchecked, accessible parent/guardian consent checkbox with a concise label. Tapping its entire row toggles it. Do not pre-check it or infer consent from tapping the main button.
- Show a prominent **Start reading** button, disabled until consent is checked. Keep the action and consent visible together on a typical phone; allow scrolling and safe-area spacing on smaller screens or with larger text.
- Do not show nickname, age, language, AR, microphone, progress, page-image checking, or cloud-narration controls on this screen. Do not include a long explanation of storage categories here; the full notice provides detail.
- Provide English and Vietnamese copy with the same meaning. No field or keyboard is needed on first run.

## Defaults and later editing

- Create the profile with no nickname, age range **5–6**, story language matching the current app/device locale (`vi` or `en`), AR enabled, and microphone disabled.
- Required core storage consent is submitted for the current server policy version. Optional progress tracking, cloud narration, and page-image checking are explicitly disabled by default. Do not change these existing privacy defaults.
- Add an editable **Child profile** area in Parent settings with age-range choices **3–4**, **5–6**, **7–8**, and an optional nickname. Show the saved age and indicate that it can affect age-based story selection and scanned-page suitability checks. Changes save through the existing profile notifier/repository; blank nickname removes it.
- Keep existing story-language, AR, and microphone controls in Parent settings, and optional data choices under **Privacy & data**. The onboarding copy should point to Parent settings without implying any optional processing is on.

## Submission and failure states

1. On **Start reading**, submit required consent and explicit optional-off values before creating the profile.
2. If consent succeeds but profile creation fails, retry profile creation using the same profile ID without resubmitting consent. Retain the visible error and allow another tap after the request finishes.
3. If current policy state is unavailable, do not guess a version or create a profile. Show the existing retryable setup error.
4. While saving, prevent duplicate submissions and indicate progress. Navigate to the home screen only after profile creation succeeds.
5. The full privacy notice remains reachable before consent and returns to the same onboarding state.

## Implementation boundaries and verification

- Keep consent and profile persistence in the existing onboarding flow; remove unused nickname/age input state and the age-pill widget if no longer used there.
- Add the profile editing UI to the existing Parent settings screen, using its current profile provider and localized strings. Avoid an additional setup route or new storage model.
- Verify first-run defaults, unchecked consent gating, privacy-before-profile ordering, retry after profile failure, Settings age/nickname edits, and English/Vietnamese copy. Run focused Flutter checks and static analysis appropriate to the touched files.
