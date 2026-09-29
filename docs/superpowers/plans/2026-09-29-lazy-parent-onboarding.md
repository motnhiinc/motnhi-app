# Quick-start Parent Onboarding Implementation Plan

> **For agentic workers:** Implement the checked tasks inline, in order. Preserve unrelated working-tree changes; do not commit without an explicit request.

**Goal:** Make first-run setup a one-consent quick start and move age/nickname editing to Parent settings.

**Architecture:** Keep server-authoritative consent and profile creation in `OnboardingScreen`; only its presentation and profile defaults change. Add a focused child-profile editor in Parent settings that writes through the existing `childProfileProvider.notifier`, rather than introducing another persistence path.

**Tech Stack:** Flutter, Riverpod, go_router, `gen-l10n`, Flutter tests.

---

## File map

- `lib/features/onboarding/onboarding_screen.dart`: quick-start layout, consent, policy notice navigation, defaults and existing retry flow.
- `lib/features/settings/settings_screen.dart`: entry point to the child profile editor.
- `lib/features/settings/child_profile_settings.dart`: editable age band and optional nickname, profile persistence and save-error feedback.
- `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb`: equivalent concise onboarding and child-profile copy; generated localizations remain generated.
- `test/privacy_localization_test.dart`: replace obsolete assertion that onboarding asks for a name; assert new disclosure keys and profile-edit copy exist.
- `test/quick_start_onboarding_test.dart`: consent gating, notice link, defaults, ordering and retry with fakes.
- `test/child_profile_settings_test.dart`: edit persistence and blank nickname removal.

### Task 1: Localized quick-start screen

- [x] Change `onboardingTitle` and `onboardingIntro` to a ready-to-read welcome and a Parent settings pointer in both ARBs. Add `onboardingDefaultAge`, `onboardingStorageTitle`, and `onboardingStorageBody` with age range, story language, chosen saved stories and optional-off meaning. Keep the existing full notice link label and required storage text for the full notice.
- [x] Replace the nickname and age cards in `OnboardingScreen` with an age-default hint, a compact disclosure, a button opening `AppRoutes.privacyNotice`, and an accessible unchecked `CheckboxListTile`-style consent row. Keep the submit button disabled until checked and display it within the initial mobile viewport.
- [x] Remove `_nickname`, `_ageBand`, `_SelectPill`, and their disposal/UI. In `ChildProfile(...)`, set `nickname: null` and `ageBand: AgeBand.fiveToSix`; preserve current locale-derived language, AR true, microphone false and all three privacy options false.
- [x] Keep `_finish` consent-before-profile ordering, current-policy check, same `_profileId` on retry, progress state, and existing error messages. Run `flutter gen-l10n` and `dart format lib/features/onboarding/onboarding_screen.dart`.

### Task 2: Later profile editing

- [x] Add a child-profile section near the top of `ReadingSettingsScreen` using `ChildProfileSettings` and the existing profile notifier. Do not edit a missing profile.
- [x] The editor shows the current age band using `AgeBand.values` and `s.yearsPill(band.min, band.max)`, and an optional nickname text field. Save via `profileNotifier.edit` against the latest profile, turning blank input into null; show busy/error states and prevent repeat saves.
- [x] Add localized `childProfileTitle`, `childProfileAgeHelp`, `childProfileSave`, and `childProfileSaveError` strings. Existing `ageBandLabel`, `nicknameLabel`, and `nicknameHint` are reused.

### Task 3: Verification

- [x] Update `privacy_localization_test.dart` to check the new EN/VI keys and remove the premise that onboarding asks for a nickname. Preserve the required-storage and cloud-copy checks.
- [x] Add focused widget tests with fake profile/privacy repositories. Assert no text field or age selector on setup, unchecked consent prevents submission, notice opens before consent, and one successful start records optional-off values before the age-5–6 profile. On a profile save failure, retry and verify privacy is not resubmitted.
- [x] Add focused editor tests for age update and nickname clearing. Run `flutter test test/quick_start_onboarding_test.dart test/child_profile_settings_test.dart test/privacy_localization_test.dart`, then `flutter analyze` and inspect the diff for unrelated changes.

## Review checks

The setup must remain scrollable under large text or a small viewport. Consent is never inferred. English and Vietnamese state the same storage behavior. The privacy notice opens without acceptance; saved age and nickname are editable later. No new privacy opt-in is introduced.
