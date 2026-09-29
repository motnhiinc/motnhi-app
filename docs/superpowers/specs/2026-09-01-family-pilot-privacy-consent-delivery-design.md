# Family Pilot Privacy and Consent Delivery Design

**Date:** 2026-09-01
**Status:** Approved delivery design, pending implementation planning
**Product design:** `docs/superpowers/specs/2026-08-28-family-pilot-privacy-consent-design.md`
**Target:** Full approved privacy scope for the coordinated family-pilot release

## 1. Purpose

Define a safe, reviewable delivery sequence for the approved family-pilot
privacy and consent design. This document does not change the locked product
decisions or data model in the product design. It defines implementation
boundaries, dependency order, failure behavior, verification, and release
activation.

The implementation will be split into changes that are independently
reviewable and mergeable, but not independently deployable. Backend enforcement
and the updated Flutter client activate together during one coordinated
maintenance window.

## 2. Delivery Approach

Use a contract-first hybrid approach:

1. Establish the transaction and privacy-state foundations.
2. Complete required consent and startup access end to end.
3. Complete optional progress tracking end to end.
4. Complete optional cloud narration end to end.
5. Add parent privacy management and history deletion.
6. Add full child-data deletion and local recovery.
7. Add inactivity retention and release verification.

This order resolves the shared transaction and consent-state constraints before
individual features consume them, while keeping later slices centered on
complete user-visible behaviors.

## 3. Architecture Boundaries

### 3.1 Backend privacy boundary

- `PrivacySettings` stores current server-authoritative privacy state.
- `ConsentEvent` stores the append-only audit trail.
- A narrow privacy repository reads and writes privacy records without
  committing transactions.
- A privacy service computes effective consent, validates policy versions, and
  coordinates privacy updates under a per-user database lock.
- A shared child-data deletion service performs manual and retention deletion.
- Protected routes own transaction commit and rollback.
- Repositories involved in protected writes use `flush()` rather than
  `commit()` so consent checks and writes remain in one transaction.
- TTS consent is checked before resolving or constructing the OpenAI service.

The per-user lock remains part of the privacy service. This work does not add a
general transaction framework.

### 3.2 Flutter privacy boundary

- `PrivacyRepository` is the only client interface to privacy endpoints.
- `PrivacyNotifier` exposes fetched server state and serializes mutations.
- A derived `AppAccessState` combines privacy and profile loading without
  treating failures as missing data.
- A reading session tracker owns the nullable session, allowed event writes,
  and the permanent stop-after-rejection behavior for one reader instance.
- Narration source selection chooses cloud or device behavior for each new
  narration operation.
- A child-data cleaner owns the local key registry, cleanup marker, generated
  file patterns, and provider invalidation.
- An ungated `/privacy-notice` route presents the complete localized notice
  before or after consent.
- Onboarding, reader tracking, narration, dashboard, and parent privacy screens
  consume effective server state rather than the legacy local consent flag.

Local values may cache rendering state but never authorize collection.

## 4. Slice Rules

- Every slice compiles and passes its focused tests before merging.
- Slices merge in order but are not deployed independently.
- API request, response, and error contracts are finalized before Flutter
  integration depends on them.
- Do not add temporary compatibility behavior or feature flags without a
  concrete need discovered during implementation.
- Backend enforcement and the updated Flutter build activate only during the
  coordinated release.
- Each capability includes backend enforcement and failure behavior, not only
  UI controls.
- Generated models are changed through their source definitions rather than by
  editing generated files.

## 5. Delivery Slices

### 5.1 Slice 1: Transaction and data foundation

**Outcome:** The backend can enforce privacy atomically without activating the
new behavior yet.

Implement:

- Privacy tables, ORM models, policy version constant, and migration defaults.
- Privacy repository and service primitives.
- Consent-event persistence in the privacy update transaction.
- Per-user locking used by consent changes and protected writes.
- Route-owned transaction handling for privacy-protected write paths.
- Repository `flush()` changes needed to preserve transaction ownership.
- Default privacy-row creation in the device-registration transaction.

Exit when migration defaults, registration invariants, rollback behavior,
consent-event atomicity, and user-lock tests pass.

### 5.2 Slice 2: Required consent and startup access

**Outcome:** New and existing families cannot write core child data without
accepting the current required disclosure.

Implement:

- `GET /v1/privacy` and `PUT /v1/privacy` contracts and stable errors.
- Flutter privacy model, repository, notifier, and `AppAccessState`.
- Consent-first onboarding with both optional choices initially off.
- Existing-family policy review and policy-version change handling.
- Correct English and Vietnamese privacy and consent copy.
- Complete English and Vietnamese privacy notice content on `/privacy-notice`,
  linked from onboarding and policy review.
- Current-policy enforcement for profile and authored-story writes.
- Retry of profile creation without renewed consent after consent succeeds.

`setupRequired` carries whether required consent still needs submission. A new
family with neither consent nor profile and a consented family whose profile
creation failed both use setup, but resume at different points. Network,
authentication, and parsing failures produce `unavailable`, never an inferred
missing profile or missing consent.

Exit when new onboarding, profile retry, existing-family review, stale-policy,
unavailable-startup, localization-alignment, and protected-core-write tests
pass.

### 5.3 Slice 3: Optional progress tracking

**Outcome:** Reading remains fully available while progress tracking is off.

Implement:

- Effective-progress checks on session and interaction-event writes.
- Reader startup without session creation when tracking is disabled.
- Nullable-session handling for page navigation, AR return, completion, and
  questions.
- A reader-instance latch that stops later writes after a backend consent
  rejection.
- Retained-history reads and dashboard states for disabled, empty, retained,
  and active tracking.

Exit when no session or event request occurs while tracking is disabled and all
reading paths still work with a null session.

### 5.4 Slice 4: Optional cloud narration

**Outcome:** Cloud narration remains off by default and device narration keeps
reading available.

Implement:

- Effective-cloud-TTS checks before constructing or invoking OpenAI services.
- Conditional Flutter HTTP narration-client creation.
- Device narration for authored stories and Scan Any Page when cloud narration
  is disabled.
- Device fallback for `cloud_tts_disabled`, network failures, and upstream
  failures.
- Preference changes applied to the next narration operation.

Exit when disabled and rejected cloud paths make no OpenAI call and authored and
scanned text remain narratable on-device.

### 5.5 Slice 5: Parent privacy management

**Outcome:** Parents can inspect privacy state, change optional choices, and
manage existing reading history.

Implement:

- Parent-gated `/parent/privacy` route and Privacy & Data screen.
- Policy version, acceptance date, stored-data summary, and privacy-notice link.
- Server-authoritative progress and cloud narration controls.
- Tracking opt-out retain/delete dialog.
- Idempotent reading-history deletion endpoint.
- Navigation from the Reading Settings privacy note.

Disabling tracking commits before the retain/delete dialog appears. Dismissing
the dialog or failing deletion retains history and does not re-enable tracking.

Exit when toggle sequencing, retained-history states, history deletion, and
profile/authored-story preservation tests pass.

### 5.6 Slice 6: Full child-data deletion and recovery

**Outcome:** Parents can delete all child data without losing the anonymous
device account needed to restart onboarding.

Implement:

- Locked, idempotent child-data deletion service and endpoint.
- Foreign-key-safe deletion across sessions, events, authored content, profile,
  and privacy records.
- Locked recreation of a fresh null-policy, optional-off privacy row on the
  first authenticated privacy fetch after deletion.
- Flutter `childDataKeys` registry and preserved-key contract.
- `child_cleanup_pending` marker and bootstrap repair.
- Disposal of data-bearing narration and AR resources before local cleanup.
- Explicit generated-audio file cleanup patterns.
- Provider invalidation and return to onboarding after cleanup.

Flutter retains all local state until server deletion succeeds. It writes the
cleanup marker before local cleanup and removes the marker last.

Exit when server deletion is atomic and idempotent, concurrent writes cannot
survive it, credentials remain, registered local data clears, unrelated files
remain, and interrupted cleanup resumes safely.

### 5.7 Slice 7: Activity retention and release readiness

**Outcome:** The complete approved retention policy and release invariant are
operational.

Implement:

- Foreground activity endpoint and Flutter once-per-calendar-day throttle.
- Throttled activity refresh from authenticated requests for older clients.
- Daily retention CLI with dry run, exact 90-day selection, lock-time recheck,
  retry safety, and content-free reporting.
- Idempotent privacy-row reconciliation.
- Coordinated maintenance and roll-forward runbook checks.

Exit when boundary, throttle, dry-run, retry, recheck, reconciliation, and
shared-deletion-service tests pass.

## 6. Critical Data Flows

### 6.1 Bootstrap

1. Device authentication establishes the anonymous user.
2. Flutter fetches privacy and profile state as separate async inputs.
3. `AppAccessState` derives `setupRequired`, `policyReviewRequired`, `ready`, or
   `unavailable`.
4. Optional consent is treated as false until server state loads successfully.

### 6.2 New-family setup

1. Flutter holds profile fields in memory.
2. The parent checks the required storage acknowledgement.
3. Optional choices remain off unless actively enabled.
4. Flutter submits privacy choices.
5. Flutter creates the profile only after consent succeeds.
6. A profile failure retries without resubmitting consent.

### 6.3 Reading

1. The reader checks effective tracking state before creating a session.
2. Disabled or unavailable tracking produces a null session.
3. Reading behavior continues with the null session.
4. `progress_tracking_disabled` permanently suppresses later tracking writes
   for that reader instance.
5. No child-facing privacy error is shown.

### 6.4 Narration

1. Flutter chooses cloud or device narration before creating the operation's
   client.
2. The backend checks consent before resolving the OpenAI service.
3. Consent rejection, network failure, or upstream failure uses device
   narration.
4. Preference changes affect the next operation and do not interrupt completed
   or in-flight audio.

### 6.5 Tracking opt-out

1. Flutter submits progress tracking as disabled.
2. The server commits revocation under the user lock.
3. Flutter immediately exposes disabled effective state.
4. The parent chooses whether to retain or delete history.
5. Dismissal or deletion failure retains history without re-enabling tracking.

### 6.6 Full deletion

1. Flutter requests server deletion while retaining local state.
2. The backend locks the user and atomically deletes child data.
3. Flutter writes `child_cleanup_pending` after server success.
4. Flutter disposes resources, removes registered keys and owned audio files,
   invalidates providers, and removes the marker last.
5. Bootstrap resumes cleanup if interruption leaves the marker present.
6. The next privacy fetch recreates only a fresh null-policy, optional-off row;
   it does not restore deleted consent, audit events, or child history.

## 7. Failure Behavior

| Failure | Required behavior |
|---|---|
| Privacy fetch fails | Show retryable unavailable startup and perform no optional collection |
| Consent succeeds and profile creation fails | Resume profile creation without renewed consent |
| Tracking write is rejected | Continue reading and suppress later tracking writes |
| Cloud narration is rejected or fails | Use device narration |
| History deletion fails | Retain history and allow retry |
| Full server deletion fails | Clear nothing locally |
| Local cleanup is interrupted | Resume cleanup during bootstrap |
| One retention deletion fails | Report a content-free failure and continue other users |

## 8. Verification Strategy

### 8.1 Backend

- Run focused `pytest` files against PostgreSQL so row-lock and concurrency
  behavior uses production database semantics.
- Test migration defaults, registration invariants, policy validation,
  transaction rollback, consent-event atomicity, and protected-write errors.
- Test no OpenAI service construction without effective consent.
- Test history and full deletion with every populated foreign-key path.
- Test revocation and deletion ordering against concurrent writes.
- Test retention boundaries, throttling, lock-time recheck, dry run, retries,
  and reconciliation.

### 8.2 Flutter

- Run focused Dart unit and provider tests for privacy state, access routing,
  nullable reading sessions, rejection latching, narration source selection,
  opt-out sequencing, cleanup, and localization meaning.
- Run `flutter analyze`.
- Do not run widget, integration, or end-to-end tests during implementation.
- Do not run `flutter run` during implementation.

Physical iOS and Android journeys, VoiceOver, and TalkBack remain part of the
coordinated pilot validation stage.

## 9. Coordinated Release

1. Enter maintenance mode and drain old API instances.
2. Apply the privacy migration and initial backfill.
3. Deploy the backend privacy endpoints, registration invariant, locks, and
   fail-closed enforcement.
4. Run idempotent privacy-row reconciliation.
5. Verify every user has exactly one privacy row.
6. Resume API traffic and release the updated Flutter build.
7. Enable the daily retention job only after the updated build is available.
8. Verify retention with a dry run before enabling mutations.

## 10. Rollback Policy

The release becomes roll-forward-only after privacy enforcement starts. An old
backend would restore unconsented protected writes.

- Before migration and enforcement, normal rollback remains available.
- After enforcement begins, failures keep the service in maintenance mode while
  the new backend is repaired.
- Operational rollback never drops privacy tables.
- Older Flutter clients may retain catalog reads but receive fail-closed errors
  for protected writes.
- Retention remains disabled until interactive privacy paths are verified.

## 11. Completion Criteria

- Required storage consent is current and server-authoritative.
- Progress tracking and cloud narration independently default off.
- Reading works without sessions, events, or cloud TTS.
- Backend bypass attempts return stable privacy errors.
- Existing families receive policy review without inferred consent.
- Parents can inspect stored data, retain or delete history, and delete all child
  data.
- Full deletion preserves only the documented technical identity and locale
  state.
- The first privacy fetch after deletion recreates an empty off-by-default row
  and returns setup-required state.
- Interrupted local cleanup repairs itself.
- Automatic retention uses the same deletion service as manual deletion.
- Reconciliation proves the one-privacy-row-per-user invariant.
- English and Vietnamese notices communicate the same data behavior.
- The complete privacy notice remains reachable without current consent.
- Focused tests and `flutter analyze` pass.
- The maintenance and roll-forward procedure is reviewed before execution.
