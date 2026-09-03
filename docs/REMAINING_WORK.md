# Remaining Work

Prioritized quality-of-life, safety, and usability work for families using the app with children ages 3-8.

## P0 - Family Pilot Blocker

- [x] Correct privacy and consent behavior.
  - Replace inaccurate device-only storage claims in English and Vietnamese.
  - Disclose required cloud storage clearly.
  - Make progress tracking optional and off by default.
  - Make cloud narration optional and off by default.
  - Keep reading available when optional tracking and cloud narration are declined.
  - Add a parent-gated Privacy & Data screen with history and child-data deletion controls.
  - Implement the approved design in `docs/superpowers/specs/2026-08-28-family-pilot-privacy-consent-design.md`.

## P1 - Parent Trust And Safety

- [ ] Remove, disable, or clearly label parent controls that are not enforced.
  - Daily reading-time limit currently saves a value but does not limit usage.
  - Content filter currently saves a value but does not control the library or recommendations.
  - Notification preference currently saves a value but has no delivery system.
  - Do not report these settings as successfully active until their behavior is implemented.

- [ ] Keep parent settings available during network failures.
  - Always render the parent dashboard shell and settings navigation.
  - Load remote reading statistics as an independent, retryable section.
  - Use specific error messages instead of a generic library error.

- [ ] Tighten parental-gate lifecycle behavior.
  - Relock when the app backgrounds or becomes inactive.
  - Relock when navigation leaves the protected parent area.
  - Add a short parent-session inactivity timeout.
  - Verify system back, deep links, settings navigation, and app switching.

## P1 - Child Daily Experience

- [ ] Make Resume Reading open the saved page.
  - Carry the latest incomplete session and `lastPageNumber` into the home view model.
  - Initialize the player and page controller at the matching page.
  - Define behavior for completed, missing, and out-of-range sessions.

- [ ] Pause narration when the app leaves the foreground.
  - Pause on inactive, paused, hidden, and detached lifecycle states.
  - Do not resume automatically without an explicit product decision.
  - Verify device lock, Home, app switching, calls, and audio interruptions.

## P2 - Accessibility

- [ ] Complete a child-focused accessibility pass.
  - Increase interactive regions to at least 48x48 logical pixels.
  - Add spoken labels to back, bedtime, previous, next, story, and locked-content controls.
  - Expose selected, checked, enabled, and locked states through semantics.
  - Prefer standard buttons, choice chips, and checkboxes over unlabeled gesture detectors.
  - Test large text, VoiceOver, and TalkBack in English and Vietnamese.
  - Consider spoken guidance for onboarding and other pre-reader flows.

## P2 - Empty And Unfinished States

- [ ] Replace generic empty and locked states with explanations and next actions.
  - Explain why a story is locked and provide an appropriate parent action.
  - Offer retry, change-filter, browse-stories, or ask-a-grown-up actions where relevant.
  - Give My Books a useful default while downloads are unavailable.

- [ ] Remove or explain inert controls.
  - Remove or implement the My Books search icon.
  - Remove or explain Download for Later while offline downloads are unavailable.
  - Avoid presenting unfinished controls as active features.

## Validation

- [ ] Add focused unit tests for privacy choices, resume position, gate lifecycle, and narration lifecycle.
- [ ] Add focused screen tests for dashboard error recovery and accessibility semantics.
- [ ] Run `flutter analyze` and the focused unit tests.
- [ ] Perform manual parent and child journey testing on physical iOS and Android devices.
- [ ] Perform VoiceOver and TalkBack testing with increased system text size.

## Recommended Delivery Order

1. Privacy and consent accuracy.
2. Misleading parent safety controls.
3. Parent settings availability during network failures.
4. True reading resume.
5. Parental-gate lifecycle.
6. Background narration pause.
7. Accessibility and touch targets.
8. Empty, locked, and unfinished states.
