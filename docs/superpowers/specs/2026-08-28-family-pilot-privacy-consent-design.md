# Family Pilot Privacy and Consent Design

**Date:** 2026-08-28
**Status:** Approved design, pending implementation planning
**Target:** Small family pilot

## 1. Purpose

Make the app's child-data behavior accurate, optional where practical, and
enforceable before inviting families into the pilot.

The current UI says reading progress stays only on the device, while production
dependency injection uses HTTP repositories for child profiles and reading
sessions. Scan and authored-story narration can also send confirmed page text to
the backend and then to OpenAI. This design replaces those conflicting claims
with explicit choices enforced by both the Flutter client and backend.

## 2. Locked Product Decisions

| Decision | Choice |
|---|---|
| Pilot model | Cloud-backed service with clear consent |
| Core app storage | Required cloud storage for the child profile and any authored story the family chooses to save |
| Progress tracking | Optional, off until the parent opts in |
| Declining tracking | Reading remains available without sessions or events |
| Cloud narration | Optional, off until the parent opts in |
| Declining cloud narration | Use on-device TTS; do not upload scan-only text for narration |
| Later tracking opt-out | Stop collection immediately, then ask whether to retain or erase existing history |
| Full deletion | Delete all child data and return to onboarding |
| Inactivity retention | Delete child data after 90 days without app activity |
| Consent authority | Versioned server state, enforced again at protected endpoints |

## 3. Scope

### 3.1 In scope

- Accurate English and Vietnamese privacy and consent copy.
- Required core-storage disclosure during onboarding.
- Separate optional choices for progress tracking and cloud narration.
- Versioned, server-authoritative consent state and audit events.
- Backend enforcement on profile, session/event, and TTS writes.
- Reading and questions without progress tracking.
- On-device narration when cloud narration is disabled.
- Parent-gated Privacy & Data screen.
- Reading-history deletion and full child-data deletion.
- Ninety-day inactivity retention using the same deletion service.
- Migration and fail-closed handling for existing pilot users.

### 3.2 Out of scope

The broader pilot hardening program will address these as separate designs:

- Daily screen-time enforcement.
- Content-filter enforcement and recommendations.
- Push notifications.
- Story downloads and full offline startup.
- Music and sound-effect playback channels.
- Stronger adult verification than the existing parental gate.
- Legal certification or a claim of COPPA compliance.

## 4. Consent Experience

### 4.1 New-family onboarding

Onboarding becomes two conceptual steps while remaining one resumable setup
flow.

1. Collect the optional nickname, age range, language, and reading preferences
   in memory.
2. Explain that those profile fields, plus any authored story the family later
   chooses to save, are stored in the app's cloud service.
3. Require an unchecked parent acknowledgement for core app storage.
4. Present progress tracking and cloud narration as separate toggles, both off.
5. Submit consent first, then create the profile.
6. If profile creation fails, retain server consent and let the parent retry
   profile creation without accepting again.

The required disclosure states what is stored and why. It covers the child
profile immediately and authored-story title/page text if the family later uses
Create Story. It must not say that the profile, authored story, or reading
history remains only on the device. It also states that no real name, birthday,
photo, voice recording, or camera image is required.

The nickname field cannot prevent a parent from typing a real name, so copy says
"nickname or first name only" rather than claiming the app can never receive a
real name.

### 4.2 Optional progress tracking

The progress choice names the collected categories:

- Stories opened and completed.
- Pages read and last-page position.
- Reading time and reading mode.
- Question choices and whether they were correct.

When disabled, reading, narration, page navigation, questions, and story
completion still work. No session or event request is sent.

When a parent disables tracking later, collection stops before any follow-up
dialog. The app then asks whether to retain existing history or permanently
delete it. Dismissing the dialog retains history and does not re-enable
tracking.

### 4.3 Optional cloud narration

The narration choice states that confirmed page text is sent through the app
backend to OpenAI to generate audio. It distinguishes three data flows:

- Camera images remain on-device and are not uploaded by the scan flow.
- Scan-only text stays on-device when cloud narration is off.
- Saving an authored story stores its title and page text in the app cloud under
  the required core-storage acceptance, regardless of whether OpenAI narration
  is enabled. The Create Story screen repeats this fact before its first save.

The notice names OpenAI, the processing purpose, and the exact data sent. It
does not make a claim about OpenAI retention unless that claim is verified
against the applicable contract and configuration.

### 4.4 Existing families and policy changes

An existing profile or authored story with no current consent record goes to a dedicated privacy
review instead of full onboarding. The parent can accept required profile
and authored-story storage or delete all child data without accepting it.
Optional choices remain off.

When the policy version changes, profile and authored-story writes pause and
optional collection is effectively disabled until the parent reviews the new
version. Existing data is retained during the review window and remains
deletable.

### 4.5 Parent Privacy & Data screen

Add `/parent/privacy` under the existing parental gate. The screen shows:

- Current policy version and acceptance date.
- Plain-language inventory of stored data.
- Progress-tracking and cloud-narration choices.
- Existing-history retain/delete flow when tracking is disabled.
- Link to the complete privacy notice.
- Destructive "Delete all child data" action with explicit confirmation.

The current privacy note in Reading Settings links to this screen. It no longer
claims reading progress is device-only.

## 5. Backend Data Model

### 5.1 `privacy_settings`

One current-state row per device user:

| Field | Type | Rule |
|---|---|---|
| `user_id` | string FK/PK | References `users.id` |
| `accepted_policy_version` | string nullable | Null until required disclosure is accepted |
| `core_storage_accepted_at` | timestamp nullable | First acceptance of the current required policy |
| `progress_tracking_enabled` | boolean | Defaults false |
| `cloud_tts_enabled` | boolean | Defaults false |
| `last_active_at` | timestamp | Drives inactivity retention |
| `updated_at` | timestamp | Last consent/preference update |

Consent is user-level because the current device account owns child profiles,
authored stories, and sessions. It also avoids requiring a profile or authored
story before consent to create either one exists.

### 5.2 `consent_events`

Append-only audit rows:

| Field | Type | Rule |
|---|---|---|
| `id` | UUID string PK | Server generated |
| `user_id` | string FK | References `users.id` |
| `scope` | string | `core_storage`, `progress_tracking`, or `cloud_tts` |
| `granted` | boolean | Granted or revoked |
| `policy_version` | string | Policy shown for this action |
| `created_at` | timestamp | Server time |

Updating privacy choices changes `privacy_settings` and appends relevant events
in one transaction. Full deletion removes both current settings and audit
events, matching the pilot's "delete all child data" promise.

The current policy version is an application constant for this pilot. A policy
content change increments it; a policy table or CMS is not introduced.

## 6. Backend API

### 6.1 `GET /v1/privacy`

Returns:

- Current and accepted policy versions.
- Whether required review is needed.
- Stored choices and their effective values.
- Acceptance and update timestamps.
- Last activity timestamp.
- Counts sufficient for a stored-data summary, without returning full history.

Effective optional consent is false when the accepted policy version is not
current, even if a stored toggle was previously true.

### 6.2 `PUT /v1/privacy`

Accepts the current policy version, required core-storage acknowledgement, and
both optional choices. It rejects an unknown or stale policy version. The
current row and consent events are committed together.

### 6.3 `POST /v1/privacy/activity`

Updates `last_active_at`. Flutter calls it when the app enters the foreground,
at most once per calendar day. Privacy updates also refresh activity.

### 6.4 `DELETE /v1/privacy/reading-history`

Deletes all interaction events and story sessions belonging to the user's
profiles or authored stories. It retains profiles, authored stories,
preferences, and consent.

The operation is idempotent and transactional.

### 6.5 `DELETE /v1/privacy/child-data`

Atomically deletes, in foreign-key-safe order:

1. Interaction events for the user's profile and authored-story sessions.
2. Story sessions for the user's profiles and authored stories.
3. Question choices belonging to questions in the user's authored stories.
4. Authored-story questions, AR scenes, narration segments, and pages.
5. User-authored stories.
6. Child profiles.
7. Consent events and privacy settings.

It retains only the anonymous `users` row and device credential needed to
restart onboarding without creating an orphan device account. The privacy
notice describes this retained technical identity and that it contains no
child profile or reading content.

The endpoint is idempotent. A retry after success returns success.

Deletion, retention rechecks, consent changes, activity updates, and every
child-data write acquire the same per-user database transaction lock. Protected
repositories do not commit internally; the route/service transaction owns the
lock through the final commit. This prevents a request that started before
deletion or revocation from committing child data afterward.

## 7. Backend Enforcement

Backend checks are authoritative; Flutter checks prevent unnecessary requests
but are not trusted as the only control.

- Profile creation/modification and authored-story creation require acceptance
  of the current required policy version.
- Session creation, session mutation, and new interaction events require
  effective progress consent.
- Existing sessions and events remain readable while tracking is off if the
  parent retained history.
- `/v1/tts` requires effective cloud-TTS consent before constructing or calling
  the OpenAI service.
- Story catalog and story-detail reads are not progress collection and remain
  available after normal authentication.
- Full deletion and privacy review remain available without current required
  consent.

Revocation and protected writes are ordered by the per-user transaction lock.
"Stops immediately" means that after the privacy update returns success, no
write that began under the previous consent state can commit. A write already
committed before revocation remains part of existing history and is handled by
the parent's retain/delete choice.

Use these stable error responses:

- `428 privacy_policy_review_required`
- `403 progress_tracking_disabled`
- `403 cloud_tts_disabled`

## 8. Flutter Architecture

### 8.1 Privacy boundary

Add a narrow `PrivacyRepository` with operations to:

- Fetch privacy state.
- Submit consent and preference changes.
- Record foreground activity.
- Delete reading history.
- Delete all child data.

A `PrivacyNotifier` exposes server truth. Local values may cache rendering state
but never authorize collection.

### 8.2 Bootstrap and routing

Add a derived `AppAccessState`:

- `loading`
- `setupRequired`
- `policyReviewRequired`
- `ready`
- `unavailable`

It combines privacy and profile state. Network or parsing failures produce a
retryable unavailable state instead of being interpreted as missing consent or
a missing profile.

### 8.3 Reader behavior

Before starting a reading session, check effective progress consent. When off,
leave the session id null. Existing null checks already allow page navigation,
questions, and completion without event writes; new tests lock this behavior.

If consent changes or the backend rejects a write during a session, stop
subsequent analytics writes and continue reading. Do not show a child-facing
privacy error.

The parent dashboard distinguishes:

- Tracking off.
- Tracking on with no history.
- Tracking on with history.
- Tracking off with retained history.

### 8.4 Narration behavior

- Do not create the HTTP narration fetcher for authored stories when effective
  cloud narration is off.
- Adapt the existing on-device file synthesizer for Scan Any Page when cloud
  narration is off.
- Treat `cloud_tts_disabled` like a recoverable narration failure and use
  on-device TTS.
- Apply preference changes to the next narration operation; an in-flight
  request may complete, but the server remains authoritative at request start.

### 8.5 Full deletion cleanup

Clear child-related local state only after server deletion succeeds. Maintain
one authoritative `childDataKeys` registry containing:

- `parent_consent` and `child_profile` legacy keys.
- `story_sessions` and `interaction_events` legacy keys.
- `reading_settings`.
- `settings_daily_limit_minutes`.
- `settings_content_filter_band`.
- `settings_notifications_enabled`.
- `ar.selected_character_id`.
- Privacy-state cache and activity-throttle keys introduced by this work.

Preserve only `device_id`, `device_secret`, `auth_user_id`, `auth_token`, and
`ui_locale_override`. Invalidate every provider that can hold a deleted value
after the key cleanup. A unit test fails when a persisted child-data key is not
registered. If local cleanup is interrupted, the next bootstrap sees no server
profile or consent and repairs the local state before showing onboarding.

Before clearing preferences, dispose narration fetchers, scan TTS clients, and
AR preparation controllers, then delete app-owned generated audio from the
temporary/cache directories. The cleaner owns explicit patterns only:
`scan_any_page_narration.(mp3|caf|wav)`, `narration_*.mp3`, and
`ar_*_p*_s*.(mp3|caf|wav)`, including their temporary-file forms. It never
deletes an entire system temporary directory. After server deletion succeeds
and before local cleanup starts, write a local `child_cleanup_pending` marker.
Preserve that marker while removing child keys and files, then remove it last.
The next bootstrap retries cleanup whenever the marker remains; if termination
happens before the marker write, the missing server profile/consent triggers the
same repair path.

## 9. Inactivity Retention

Implement one idempotent backend deletion service used by manual deletion and
automatic retention. Expose retention as a CLI command for a daily deployment
cron/job rather than running a scheduler inside the API process.

Authenticated API activity also refreshes `last_active_at`, throttled to at most
one write per user per day. This server-side touch keeps active older builds
from being misclassified even though they do not call the new foreground
endpoint. The explicit foreground endpoint remains the primary updated-client
signal.

The command:

- Selects child-data owners with `last_active_at` strictly older than 90 days.
- Acquires the per-user transaction lock, then rechecks `last_active_at` inside
  the deletion transaction before mutating anything.
- Supports dry-run output.
- Calls the shared deletion service per user.
- Is safe to retry after interruption.
- Reports attempted, deleted, skipped, and failed counts without logging child
  content.

At migration time, existing users with child data receive `last_active_at` set
to deployment time, giving them a full 90-day review window. The Privacy screen
states that child data is deleted after 90 days without app activity. Device
accounts have no verified contact address, so the pilot does not promise an
email warning.

## 10. Migration and Rollout

The migration creates both tables and inserts a privacy-settings row for every
existing user, including users who own authored stories without a profile. New
device registration creates the default privacy-settings row in the same
transaction as `users` and `devices`. The migration does not infer prior
consent. Optional choices are false and accepted policy version is null.

Deploy during a coordinated pilot maintenance window. Old API instances must
be drained before the migration backfill, and device registration and child-data
writes remain unavailable until the new backend is serving. Run an idempotent
privacy-row reconciliation after all old instances stop and before traffic
resumes; it covers a registration that committed immediately before draining.

Deployment order:

1. Enter maintenance mode and drain old API instances.
2. Run the database migration and initial all-user backfill.
3. Deploy the backend privacy endpoints, registration update, locks, and
   fail-closed enforcement.
4. Run privacy-row reconciliation and verify no user lacks a row.
5. Resume API traffic and release the updated Flutter build.
6. Enable the daily retention job after the updated build is available.

Older clients may temporarily lose profile/authored-story writes, progress
writes, and cloud TTS. This is deliberate: the rollout favors stopping
collection over an observe-only compatibility period. Story catalog reads
continue to work.

## 11. Error Handling

- Privacy fetch failure: show a retryable startup state; optional collection is
  off.
- Profile creation failure after consent: keep consent and retry profile
  creation.
- Session consent rejection: continue reading without tracking.
- TTS consent rejection or network failure: use on-device TTS.
- History deletion failure: keep the retained history state and allow retry.
- Full deletion failure: keep local credentials and state; clear nothing until
  the server transaction succeeds.
- Local cleanup interruption after server deletion: repair on next bootstrap.
- Retention failure for one user: record a content-free error and continue with
  other eligible users.

## 12. Verification

### 12.1 Backend tests

- New and migrated consent defaults are off.
- Stale and unknown policy versions are rejected.
- Privacy updates and audit events commit together.
- Every profile write requires current required consent.
- Every authored-story creation requires current required consent, including a
  user who has no profile.
- Every session/event write requires effective progress consent.
- Existing history remains readable while tracking is disabled.
- TTS rejects before constructing or calling the external service.
- Reading-history deletion preserves profile and authored stories.
- Full deletion clears every child-data table and preserves device auth.
- Full deletion handles populated question-choice, question, page, segment,
  scene, story, profile, session, and event foreign keys and is idempotent.
- Concurrent profile/story/session/event writes cannot survive successful full
  deletion.
- Consent revocation is ordered against in-flight writes; no protected write
  commits after revocation returns.
- Retention respects the exact 90-day boundary.
- Retention rechecks activity under lock before deletion.
- Authenticated activity from an older client prevents retention deletion.
- Retention dry-run mutates nothing and retries safely.

### 12.2 Flutter unit tests

- Every `AppAccessState` and route decision.
- Both optional choices default off.
- Tracking off creates no session or event requests.
- Mid-session revocation stops normal page, AR-return, completion, and question
  event paths after the first consent rejection.
- Questions and story completion work with a null session.
- Dashboard distinguishes disabled, empty, retained, and active states.
- Cloud narration off creates no HTTP TTS request.
- Authored-story TTS rejection falls back to device narration.
- Scan Any Page selects the on-device file synthesizer when consent is off and
  falls back to it after a server consent rejection.
- Tracking opt-out retain/delete branches.
- Every key in `childDataKeys` clears only after successful full deletion, all
  preserved keys remain, and live providers are invalidated.
- Generated scan, authored-narration, and AR audio files are removed without
  touching unrelated temporary files; interrupted cleanup retries on bootstrap.
- Bootstrap repairs stale local state after server deletion.
- English and Vietnamese consent meaning remains aligned.

Use `flutter analyze`, focused Dart unit tests, and focused backend tests. Widget,
integration, and end-to-end test execution is excluded from the development
loop under the project testing constraints.

## 13. Acceptance Criteria

- No user-facing copy claims cloud profile or progress data is device-only.
- A parent actively accepts current required core-storage disclosure.
- Progress and cloud narration start off and are independently optional.
- Reading works without progress tracking or cloud narration.
- Backend endpoints reject unauthorized collection even if the client is
  bypassed.
- The parent can inspect choices, delete history, and delete all child data.
- Manual and retention deletion share one tested service.
- Existing users receive no inferred consent and get a full review window.
- No deployment window can create a user without `privacy_settings`; the
  reconciliation proves the invariant before traffic resumes.
- The app names the external narration provider and data sent without making an
  unverified retention promise.

## 14. Follow-Up Workstreams

After this privacy workstream is implemented, design the remaining pilot
hardening work independently in this order:

1. Parental safety controls: enforce daily limits and content filtering, then
   tighten parent-gate lifecycle behavior.
2. Offline and media: downloads, cached startup/story access, narration assets,
   music, and sound-effect channels.
3. Notifications: permission timing, learning reports, book suggestions,
   scheduling, delivery, and opt-out.
