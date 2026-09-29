# Family Pilot Privacy and Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement server-authoritative required storage consent, optional progress tracking and cloud narration, parent data controls, full deletion, and 90-day inactivity retention without blocking reading when optional collection is declined.

**Architecture:** Establish a PostgreSQL-backed privacy boundary and route-owned protected transactions before connecting Flutter to the new contract. Flutter derives startup access from independent privacy/profile state, centralizes session tracking and narration selection, and clears local child data only after atomic server deletion succeeds. All changes merge in tested slices but activate together during a coordinated, roll-forward release.

**Tech Stack:** Flutter/Dart, Riverpod 3, GoRouter, Dio, Freezed/json_serializable, SharedPreferences, FastAPI, SQLAlchemy 2, PostgreSQL 16, Alembic, pytest.

---

## Source Documents

- Product behavior: `docs/superpowers/specs/2026-08-28-family-pilot-privacy-consent-design.md`
- Delivery design: `docs/superpowers/specs/2026-09-01-family-pilot-privacy-consent-delivery-design.md`
- Work item: `docs/REMAINING_WORK.md:5-14`

If this plan and the product design differ, the product design wins unless this
plan explicitly records a later approved clarification.

## Locked Implementation Decisions

- `CURRENT_PRIVACY_POLICY_VERSION = "2026-08-28"`.
- Stable backend errors use FastAPI's existing body shape, for example
  `{"detail":"progress_tracking_disabled"}`.
- `PUT /v1/privacy` is full replacement. Every request sends policy version,
  required acknowledgement, progress choice, and cloud-TTS choice.
- A first acceptance or a policy-version change appends events for all three
  scopes. A repeated PUT for the same policy appends only scopes whose stored
  value changed.
- `core_storage_accepted_at` changes when a new policy version is accepted and
  remains unchanged for repeated updates under the same version.
- Privacy timestamps and once-per-day activity throttling use UTC.
- Stored-data counts are `child_profiles`, `authored_stories`,
  `story_sessions`, and `interaction_events`.
- The startup review route is `/privacy-review`; the complete notice route is
  the ungated `/privacy-notice`; parent controls remain `/parent/privacy`.
- The authored-story storage disclosure appears once per fresh composer flow,
  immediately before its first save attempt. It creates no persisted key.
- Cloud narration failures fall back to on-device narration. Invalid or empty
  input remains a validation error before narration begins.
- `child_cleanup_pending` is an orchestration marker, not a child-data key. It
  survives child-key removal and is removed last.
- The privacy fetch recreates a missing privacy row after full deletion under a
  lock on `users.id`.
- Authenticated activity updates an existing privacy row at most once per UTC
  date. It never recreates a missing row; `GET /v1/privacy` owns recreation.
- Existing per-story deletion remains available during policy review because it
  reduces stored child data.
- No migration, deployment, retention mutation, `flutter run`, widget test,
  integration test, or E2E test is executed during implementation.

## File Structure

### Backend files to create

- `backend/migrations/versions/0005_privacy_consent.py`: schema and all-user backfill.
- `backend/app/repositories/privacy.py`: flush-only privacy persistence and counts.
- `backend/app/services/privacy.py`: policy rules, user lock, consent checks, activity.
- `backend/app/services/child_data_deletion.py`: shared FK-safe deletion service.
- `backend/app/routers/privacy.py`: privacy, activity, and deletion endpoints.
- `backend/privacy_retention.py`: dry-run-capable retention CLI.
- `backend/privacy_reconcile.py`: one-row-per-user reconciliation CLI.
- Focused tests under `backend/tests/test_privacy_*.py` and
  `backend/tests/test_child_data_deletion.py`.

### Flutter files to create

- `lib/data/models/privacy_state.dart`: server privacy DTO and summary counts.
- `lib/data/repositories/privacy_repository.dart`: narrow client contract.
- `lib/data/repositories/http_privacy_repository.dart`: Dio implementation.
- `lib/data/sources/persistence_keys.dart`: authoritative persistence-key registry.
- `lib/features/privacy/privacy_providers.dart`: notifier and access derivation.
- `lib/features/privacy/privacy_review_screen.dart`: required policy review.
- `lib/features/privacy/privacy_notice_screen.dart`: ungated localized notice.
- `lib/features/privacy/privacy_screen.dart`: parent Privacy & Data controls.
- `lib/features/privacy/child_data_cleaner.dart`: ordered local cleanup and repair.
- `lib/features/privacy/privacy_activity_notifier.dart`: foreground UTC-day throttle.
- `lib/features/player/reading_session_tracker.dart`: nullable/latching tracker.
- `lib/features/player/narration_source_selection.dart`: per-operation source policy.
- `lib/features/scan_any_page/device_tts_client.dart`: on-device file TTS adapter.
- Focused unit/provider tests under `test/` with matching names.

Generated Freezed/JSON files are produced by `build_runner`. Generated
localization Dart files are produced by `flutter gen-l10n` and are gitignored;
never edit them manually.

---

## Slice 1: Transaction and Data Foundation

### Task 1: Add privacy schema and migration

**Files:**
- Modify: `backend/app/models/__init__.py`
- Create: `backend/migrations/versions/0005_privacy_consent.py`
- Create: `backend/tests/test_privacy_migration.py`

- [ ] **Step 1: Write the migration test**

Create tests that upgrade a temporary PostgreSQL schema from revision
`c4b1f70a5d38`, insert users before the privacy migration, upgrade to head, and
assert one row per user with null acceptance, both choices false, and non-null
UTC timestamps. Add a downgrade assertion that removes both privacy tables.

```python
def test_privacy_migration_backfills_defaults(connection):
    connection.execute(sa.text("INSERT INTO users (id, auth_provider, created_at, updated_at) VALUES ('u1', 'device', now(), now())"))
    command.upgrade(alembic_config(connection), "head")
    row = connection.execute(sa.text("SELECT * FROM privacy_settings WHERE user_id = 'u1'" )).mappings().one()
    assert row["accepted_policy_version"] is None
    assert row["core_storage_accepted_at"] is None
    assert row["progress_tracking_enabled"] is False
    assert row["cloud_tts_enabled"] is False
    assert row["last_active_at"] is not None
    assert row["updated_at"] is not None
```

- [ ] **Step 2: Run the migration test and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_migration.py -v`

Expected: FAIL because revision `0005_privacy_consent` and the privacy tables do
not exist.

- [ ] **Step 3: Add the ORM models**

Add these source definitions to `backend/app/models/__init__.py`:

```python
class PrivacySettings(Base):
    __tablename__ = "privacy_settings"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    accepted_policy_version: Mapped[str | None] = mapped_column(Text, nullable=True)
    core_storage_accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    progress_tracking_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    cloud_tts_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    last_active_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ConsentEvent(Base):
    __tablename__ = "consent_events"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    scope: Mapped[str] = mapped_column(Text)
    granted: Mapped[bool] = mapped_column(Boolean)
    policy_version: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
```

- [ ] **Step 4: Implement migration `0005_privacy_consent.py`**

Use `revision = "9b6f5f37f8a1"`, `down_revision = "c4b1f70a5d38"`. Create
the two tables and indexes matching the ORM definitions. Backfill with one SQL
statement using database time:

```python
op.execute("""
    INSERT INTO privacy_settings (
        user_id, accepted_policy_version, core_storage_accepted_at,
        progress_tracking_enabled, cloud_tts_enabled, last_active_at, updated_at
    )
    SELECT id, NULL, NULL, FALSE, FALSE, now(), now()
    FROM users
    ON CONFLICT (user_id) DO NOTHING
""")
```

Downgrade drops consent-event indexes/table before privacy indexes/table.

- [ ] **Step 5: Verify migration and model tests**

Run: `cd backend && uv run pytest tests/test_privacy_migration.py -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/models/__init__.py backend/migrations/versions/0005_privacy_consent.py backend/tests/test_privacy_migration.py
git commit -m "feat(privacy): add consent schema"
```

### Task 2: Add privacy persistence and user locking

**Files:**
- Create: `backend/app/repositories/privacy.py`
- Create: `backend/app/services/privacy.py`
- Create: `backend/tests/test_privacy_foundation.py`
- Modify: `backend/tests/conftest.py`

- [ ] **Step 1: Add failing foundation tests**

Test these exact behaviors with independent PostgreSQL sessions where locking is
involved: `test_effective_choices_require_current_policy`,
`test_lock_user_uses_retained_user_row`,
`test_update_appends_all_scopes_on_first_acceptance`,
`test_repeated_update_appends_only_changed_scope`, and
`test_update_and_events_roll_back_together`.

The first acceptance must yield scopes
`{"core_storage", "progress_tracking", "cloud_tts"}`. A same-version change
from progress false to true must append only `progress_tracking`.

- [ ] **Step 2: Run tests and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_foundation.py -v`

Expected: FAIL because privacy repository/service modules do not exist.

- [ ] **Step 3: Implement the flush-only repository**

Implement these exact functions in `backend/app/repositories/privacy.py`:

```python
def get_settings(db: Session, user_id: str) -> PrivacySettings | None:
    return db.get(PrivacySettings, user_id)


def create_default_settings(
    db: Session, user_id: str, now: datetime
) -> PrivacySettings:
    settings = PrivacySettings(
        user_id=user_id,
        accepted_policy_version=None,
        core_storage_accepted_at=None,
        progress_tracking_enabled=False,
        cloud_tts_enabled=False,
        last_active_at=now,
        updated_at=now,
    )
    db.add(settings)
    db.flush()
    return settings


def add_event(db: Session, user_id: str, scope: str, granted: bool,
              policy_version: str, now: datetime) -> ConsentEvent:
    event = ConsentEvent(
        id=str(uuid.uuid4()), user_id=user_id, scope=scope, granted=granted,
        policy_version=policy_version, created_at=now,
    )
    db.add(event)
    db.flush()
    return event
```

Also implement `data_counts(db, user_id)`,
`retention_candidate_ids(db, cutoff)`, and `missing_privacy_user_ids(db)` with
SQLAlchemy `count`, `distinct`, `exists`, and ownership joins. `data_counts()`
returns only `child_profiles`, `authored_stories`, `story_sessions`, and
`interaction_events`; sessions/events count when either their profile or story
is owned by the user. Retention candidates require an owned profile or authored
story and `last_active_at < cutoff`. None of these functions commits.

- [ ] **Step 4: Implement the privacy service contract**

Expose these definitions from `backend/app/services/privacy.py`:

```python
CURRENT_PRIVACY_POLICY_VERSION = "2026-08-28"

class PrivacyError(Exception):
    def __init__(self, status_code: int, code: str):
        self.status_code = status_code
        self.code = code

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

def lock_user(db: Session, user_id: str) -> User:
    user = db.scalar(select(User).where(User.id == user_id).with_for_update())
    if user is None:
        raise PrivacyError(401, "unknown_user")
    return user

def effective_progress(settings: PrivacySettings | None) -> bool:
    return bool(settings and settings.accepted_policy_version == CURRENT_PRIVACY_POLICY_VERSION
                and settings.progress_tracking_enabled)

def effective_cloud_tts(settings: PrivacySettings | None) -> bool:
    return bool(settings and settings.accepted_policy_version == CURRENT_PRIVACY_POLICY_VERSION
                and settings.cloud_tts_enabled)

def require_core_storage(settings: PrivacySettings | None) -> None:
    if settings is None or settings.accepted_policy_version != CURRENT_PRIVACY_POLICY_VERSION:
        raise PrivacyError(428, "privacy_policy_review_required")


def require_progress(settings: PrivacySettings | None) -> None:
    if not effective_progress(settings):
        raise PrivacyError(403, "progress_tracking_disabled")


def require_cloud_tts(settings: PrivacySettings | None) -> None:
    if not effective_cloud_tts(settings):
        raise PrivacyError(403, "cloud_tts_disabled")
```

Implement `update_settings(db, user_id, *, policy_version,
core_storage_accepted, progress_tracking_enabled, cloud_tts_enabled)` returning
`PrivacySettings`. It rejects any version other than the current version with
`PrivacyError(428, "privacy_policy_review_required")`, rejects an unchecked core
acknowledgement with the same error, locks `users`, creates a missing default
row, applies the locked event rules, refreshes `last_active_at`/`updated_at`, and
flushes without committing.

- [ ] **Step 5: Add independent-session test fixtures**

Add factories to `backend/tests/conftest.py` that open separate engine
connections and sessions and close/rollback them in fixture teardown. Do not
reuse the normal shared `db` fixture for row-lock tests.

- [ ] **Step 6: Verify foundation tests**

Run: `cd backend && uv run pytest tests/test_privacy_foundation.py -v`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/repositories/privacy.py backend/app/services/privacy.py backend/tests/test_privacy_foundation.py backend/tests/conftest.py
git commit -m "feat(privacy): add server privacy boundary"
```

### Task 3: Move protected write commits to routes

**Files:**
- Modify: `backend/app/repositories/profiles.py`
- Modify: `backend/app/repositories/stories.py`
- Modify: `backend/app/repositories/sessions.py`
- Modify: `backend/app/routers/profiles.py`
- Modify: `backend/app/routers/stories.py`
- Modify: `backend/app/routers/sessions.py`
- Modify: `backend/tests/test_profiles.py`
- Modify: `backend/tests/test_authored_stories.py`
- Modify: `backend/tests/test_sessions.py`

- [ ] **Step 1: Add rollback and atomic-event tests**

Add tests proving repositories flush without committing, and add
`test_start_session_and_started_event_are_one_transaction` plus
`test_complete_session_and_completed_event_are_one_transaction`. Force a route
failure after the repository flush and assert both the session mutation and its
automatic event are absent after rollback.

- [ ] **Step 2: Run focused tests and verify failure**

Run: `cd backend && uv run pytest tests/test_profiles.py tests/test_authored_stories.py tests/test_sessions.py -v`

Expected: the new transaction tests FAIL because repositories commit internally.

- [ ] **Step 3: Replace repository commits with flushes**

In `profiles.upsert`, `stories.create_authored`, `stories.delete_authored`,
`sessions.start`, `sessions.patch`, and `sessions.record_event`, replace internal
commits with `db.flush()`. Remove `db.refresh()` calls that require a commit;
flush and refresh within the active transaction when response serialization
needs server values.

- [ ] **Step 4: Add route-owned transaction completion**

For each affected write route, use route-owned `try`/commit/rollback after all
checks. For profile creation the exact control shape is:

```python
try:
    result = repo.upsert(db, user.id, body.model_dump())
    db.commit()
    return result
except Exception:
    db.rollback()
    raise
```

Do not wrap the route in `with db.begin()` because authentication has already
started a SQLAlchemy transaction on the shared dependency session.

- [ ] **Step 5: Verify protected-write regressions**

Run: `cd backend && uv run pytest tests/test_profiles.py tests/test_authored_stories.py tests/test_sessions.py -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/repositories/profiles.py backend/app/repositories/stories.py backend/app/repositories/sessions.py backend/app/routers/profiles.py backend/app/routers/stories.py backend/app/routers/sessions.py backend/tests/test_profiles.py backend/tests/test_authored_stories.py backend/tests/test_sessions.py
git commit -m "refactor(privacy): centralize protected transactions"
```

### Task 4: Create privacy state during device registration

**Files:**
- Modify: `backend/app/routers/auth.py`
- Modify: `backend/tests/test_auth.py`

- [ ] **Step 1: Add registration invariant tests**

Assert that a new device request creates `User`, `Device`, and default
`PrivacySettings` in one commit, while an invalid or rolled-back registration
creates none of them.

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_auth.py -v`

Expected: FAIL because registration does not create privacy state.

- [ ] **Step 3: Add the default privacy row before registration commit**

After adding `Device` and before `db.commit()`, call:

```python
privacy_repo.create_default_settings(db, user.id, now)
```

Keep the existing single registration commit.

- [ ] **Step 4: Verify auth tests**

Run: `cd backend && uv run pytest tests/test_auth.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/auth.py backend/tests/test_auth.py
git commit -m "feat(privacy): initialize device privacy state"
```

---

## Slice 2: Required Consent and Startup Access

### Task 5: Add privacy API schemas and endpoints

**Files:**
- Modify: `backend/app/schemas/__init__.py`
- Create: `backend/app/routers/privacy.py`
- Modify: `backend/app/main.py`
- Create: `backend/tests/test_privacy_api.py`

- [ ] **Step 1: Add failing contract tests**

Test unauthenticated rejection, default GET, full PUT, stale version, unchecked
core acknowledgement, effective-choice calculation, summary counts, and locked
row recreation after full deletion.

Expected response shape:

```json
{
  "current_policy_version": "2026-08-28",
  "accepted_policy_version": null,
  "review_required": true,
  "core_storage_accepted_at": null,
  "progress_tracking_enabled": false,
  "cloud_tts_enabled": false,
  "effective_progress_tracking_enabled": false,
  "effective_cloud_tts_enabled": false,
  "last_active_at": "2026-09-01T00:00:00Z",
  "updated_at": "2026-09-01T00:00:00Z",
  "counts": {
    "child_profiles": 0,
    "authored_stories": 0,
    "story_sessions": 0,
    "interaction_events": 0
  }
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_api.py -v`

Expected: FAIL with 404 for `/v1/privacy`.

- [ ] **Step 3: Add Pydantic schemas**

Add exact classes:

```python
class PrivacyUpdateRequest(BaseModel):
    policy_version: str
    core_storage_accepted: bool
    progress_tracking_enabled: bool
    cloud_tts_enabled: bool

class PrivacyDataCounts(BaseModel):
    child_profiles: int
    authored_stories: int
    story_sessions: int
    interaction_events: int

class PrivacyStateResponse(BaseModel):
    current_policy_version: str
    accepted_policy_version: str | None
    review_required: bool
    core_storage_accepted_at: datetime | None
    progress_tracking_enabled: bool
    cloud_tts_enabled: bool
    effective_progress_tracking_enabled: bool
    effective_cloud_tts_enabled: bool
    last_active_at: datetime
    updated_at: datetime
    counts: PrivacyDataCounts
```

- [ ] **Step 4: Implement GET and PUT routes**

`GET /v1/privacy` locks `users`, creates a missing default row, commits only if
it created the row, and returns the complete response. `PUT /v1/privacy` calls
the service, commits state and events together, maps `PrivacyError` to
`HTTPException(status_code=error.status_code, detail=error.code)`, and returns
the same response shape.

- [ ] **Step 5: Register the router and verify**

Add `privacy.router` to `backend/app/main.py` and run:

`cd backend && uv run pytest tests/test_privacy_api.py -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/schemas/__init__.py backend/app/routers/privacy.py backend/app/main.py backend/tests/test_privacy_api.py
git commit -m "feat(privacy): expose privacy state API"
```

### Task 6: Enforce required consent on core writes

**Files:**
- Modify: `backend/app/routers/profiles.py`
- Modify: `backend/app/routers/stories.py`
- Modify: `backend/tests/test_profiles.py`
- Modify: `backend/tests/test_authored_stories.py`

- [ ] **Step 1: Add fail-closed tests**

Cover profile create, profile patch, and authored-story create for missing,
stale, and current consent. Include an authored-story owner with no profile.
Verify catalog/detail reads and per-story deletion remain available.

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_profiles.py tests/test_authored_stories.py -v`

Expected: new fail-closed cases FAIL because writes are currently accepted.

- [ ] **Step 3: Lock, check, write, and commit**

In each protected route execute lock, fetch privacy, require core storage, write,
and commit in that order. Profile creation uses:

```python
privacy_service.lock_user(db, user.id)
settings = privacy_repo.get_settings(db, user.id)
privacy_service.require_core_storage(settings)
result = repo.upsert(db, user.id, body.model_dump())
db.commit()
return result
```

Profile patch passes its existing merged dictionary to `repo.upsert`.
Authored-story creation passes `body` to `repo.create_authored`. Each route
rolls back on `PrivacyError` or any write failure.

Map `PrivacyError` to `428 {"detail":"privacy_policy_review_required"}` and
rollback before raising.

- [ ] **Step 4: Verify core-write tests**

Run: `cd backend && uv run pytest tests/test_profiles.py tests/test_authored_stories.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/profiles.py backend/app/routers/stories.py backend/tests/test_profiles.py backend/tests/test_authored_stories.py
git commit -m "feat(privacy): require consent for child data writes"
```

### Task 7: Add Flutter privacy DTO and repository contract

**Files:**
- Create: `lib/data/models/privacy_state.dart`
- Modify: `lib/data/models/models.dart`
- Create: `lib/data/repositories/privacy_repository.dart`
- Create: `lib/data/repositories/http_privacy_repository.dart`
- Modify: `lib/core/di.dart`
- Modify: `test/http_repositories_test.dart`

- [ ] **Step 1: Add failing HTTP contract tests**

Use `DioAdapter` to assert exact methods, paths, snake-case bodies, response
decoding, and error codes for fetch/update/activity/history deletion/full
deletion.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/http_repositories_test.dart`

Expected: FAIL because privacy repository classes do not exist.

- [ ] **Step 3: Define the Freezed models**

```dart
@freezed
abstract class PrivacyDataCounts with _$PrivacyDataCounts {
  const factory PrivacyDataCounts({
    @Default(0) int childProfiles,
    @Default(0) int authoredStories,
    @Default(0) int storySessions,
    @Default(0) int interactionEvents,
  }) = _PrivacyDataCounts;
  factory PrivacyDataCounts.fromJson(Map<String, dynamic> json) =>
      _$PrivacyDataCountsFromJson(json);
}

@freezed
abstract class PrivacyState with _$PrivacyState {
  const factory PrivacyState({
    required String currentPolicyVersion,
    String? acceptedPolicyVersion,
    required bool reviewRequired,
    DateTime? coreStorageAcceptedAt,
    @Default(false) bool progressTrackingEnabled,
    @Default(false) bool cloudTtsEnabled,
    @Default(false) bool effectiveProgressTrackingEnabled,
    @Default(false) bool effectiveCloudTtsEnabled,
    required DateTime lastActiveAt,
    required DateTime updatedAt,
    @Default(PrivacyDataCounts()) PrivacyDataCounts counts,
  }) = _PrivacyState;
  factory PrivacyState.fromJson(Map<String, dynamic> json) =>
      _$PrivacyStateFromJson(json);
}
```

- [ ] **Step 4: Define repository interface and typed failure**

```dart
abstract interface class PrivacyRepository {
  Future<PrivacyState> fetchPrivacy();
  Future<PrivacyState> updatePrivacy({
    required String policyVersion,
    required bool coreStorageAccepted,
    required bool progressTrackingEnabled,
    required bool cloudTtsEnabled,
  });
  Future<void> recordActivity();
  Future<void> deleteReadingHistory();
  Future<void> deleteChildData();
}

class PrivacyFailure implements Exception {
  const PrivacyFailure(this.code);
  final String code;
}
```

Implement the HTTP repository using `/v1/privacy`, `/v1/privacy/activity`,
`/v1/privacy/reading-history`, and `/v1/privacy/child-data`. Decode FastAPI's
`response.data['detail']` before falling back to `network` or `invalid_response`.

- [ ] **Step 5: Register DI and generate models**

Add `privacyRepositoryProvider` in `lib/core/di.dart`, export the model, then run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/http_repositories_test.dart
```

Expected: generation succeeds and tests PASS.

- [ ] **Step 6: Commit source and generated model files**

```bash
git add lib/data/models/privacy_state.dart lib/data/models/privacy_state.freezed.dart lib/data/models/privacy_state.g.dart lib/data/models/models.dart lib/data/repositories/privacy_repository.dart lib/data/repositories/http_privacy_repository.dart lib/core/di.dart test/http_repositories_test.dart
git commit -m "feat(privacy): add Flutter privacy contract"
```

### Task 8: Derive fail-closed app access and routing

**Files:**
- Create: `lib/features/privacy/privacy_providers.dart`
- Modify: `lib/features/profile/profile_providers.dart`
- Modify: `lib/core/router/app_router.dart`
- Create: `test/privacy_providers_test.dart`
- Create: `test/app_access_state_test.dart`

- [ ] **Step 1: Add the access-state matrix tests**

Cover privacy/profile loading, errors, no consent/no profile, accepted/no
profile, stale consent/existing profile, current consent/profile, and privacy
optional values before fetch.

```dart
enum AppAccessStatus { loading, setupRequired, policyReviewRequired, ready, unavailable }

class AppAccessState {
  const AppAccessState(this.status, {this.consentAlreadySubmitted = false});
  final AppAccessStatus status;
  final bool consentAlreadySubmitted;
}
```

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/privacy_providers_test.dart test/app_access_state_test.dart`

Expected: FAIL because providers do not exist.

- [ ] **Step 3: Implement `PrivacyNotifier`**

Use `AsyncNotifier<PrivacyState>` with `build()` calling `fetchPrivacy()`.
Mutations serialize by awaiting the current mutation before starting the next,
set `AsyncData` only from server responses, and preserve the previous data in a
separate local variable for retry UI without treating it as authorization.
After each successful fetch/update, serialize the response to
`privacy_state_cache`. Expose that value through a separate display-only
provider for unavailable/retry UI. `AppAccessState`, effective tracking, and
effective narration providers must read only the fresh async server result.

- [ ] **Step 4: Implement access derivation**

Derive `unavailable` from either async error, `loading` while either input is
loading, `policyReviewRequired` when a profile exists and privacy review is
required, `setupRequired(consentAlreadySubmitted: false)` for a new family,
`setupRequired(consentAlreadySubmitted: true)` after consent succeeded but no
profile exists, and `ready` only for current consent plus profile.

- [ ] **Step 5: Replace router redirects**

Add routes `/privacy-review` and `/privacy-notice`. Redirect by status:

```dart
switch (access.status) {
  case AppAccessStatus.loading:
  case AppAccessStatus.unavailable:
    return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  case AppAccessStatus.setupRequired:
    return loc == AppRoutes.onboarding || loc == AppRoutes.privacyNotice
        ? null : AppRoutes.onboarding;
  case AppAccessStatus.policyReviewRequired:
    return loc == AppRoutes.privacyReview || loc == AppRoutes.privacyNotice
        ? null : AppRoutes.privacyReview;
  case AppAccessStatus.ready:
    if (loc == AppRoutes.onboarding || loc == AppRoutes.privacyReview) {
      return AppRoutes.home;
    }
}
```

Keep `/privacy-notice` ungated and retain the existing `/parent*` gate.

- [ ] **Step 6: Verify provider/router logic**

Run: `flutter test test/privacy_providers_test.dart test/app_access_state_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/privacy/privacy_providers.dart lib/features/profile/profile_providers.dart lib/core/router/app_router.dart test/privacy_providers_test.dart test/app_access_state_test.dart
git commit -m "feat(privacy): derive fail-closed app access"
```

### Task 9: Replace onboarding consent and add policy review/notice

**Files:**
- Modify: `lib/features/onboarding/onboarding_screen.dart`
- Create: `lib/features/privacy/privacy_review_screen.dart`
- Create: `lib/features/privacy/privacy_notice_screen.dart`
- Modify: `lib/data/repositories/profile_repository.dart`
- Modify: `lib/data/repositories/http_profile_repository.dart`
- Modify: `lib/data/repositories/authored_story_repository.dart`
- Modify: `lib/data/repositories/http_authored_story_repository.dart`
- Modify: `lib/features/story_composer/story_composer_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_vi.arb`
- Create: `test/privacy_localization_test.dart`
- Modify: `test/story_composer_controller_test.dart`

- [ ] **Step 1: Add localization and flow tests**

Assert both ARBs contain matching keys for required storage, optional tracking,
OpenAI narration, retention, deletion, retry, policy review, and complete-notice
sections. Assert no EN/VI source string claims profile or progress is device-only.
Assert onboarding asks for a "nickname or first name only" and does not claim a
real name is technically impossible. Required-storage copy names profile fields
and later saved authored-story title/page text; it states that real name,
birthday, photo, voice recording, and camera image are not required. Cloud
narration copy states that confirmed page text goes through the app backend to
OpenAI, camera images remain on-device, and scan-only text remains on-device when
cloud narration is off.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/privacy_localization_test.dart test/story_composer_controller_test.dart`

Expected: FAIL because the copy and flow do not exist.

- [ ] **Step 3: Remove consent from `ProfileRepository`**

Keep only:

```dart
abstract class ProfileRepository {
  Future<ChildProfile?> getProfile();
  Future<void> saveProfile(ChildProfile profile);
}
```

Remove `KeyValueStore` from `HttpProfileRepository`. Map backend detail
`privacy_policy_review_required` to a typed `ProfileFailure` and do the same for
authored-story creation.

- [ ] **Step 4: Implement consent-first onboarding**

Keep profile fields in widget state. Add unchecked required acknowledgement and
two optional switches initialized false. `_finish()` first calls
`PrivacyNotifier.updatePrivacy` with the four complete request fields; only
after success calls profile save. If privacy
already matches current acceptance because a prior profile save failed, retry
only profile save. Loading and retry UI must distinguish privacy failure from
profile failure.

- [ ] **Step 5: Implement review and notice screens**

`PrivacyReviewScreen` offers current required disclosure, optional choices off,
`Review and continue`, `Read full privacy notice`, and `Delete all child data`.
`PrivacyNoticeScreen` is read-only, scrollable, and includes localized sections:
stored data, progress choice, cloud narration/OpenAI, camera/scan handling,
retention, deletion, and retained anonymous device identity.

- [ ] **Step 6: Add authored-story disclosure**

Before the first save attempt in each fresh composer flow, show a confirmation
that title and page text will be stored in the app cloud. Continue invokes the
existing save; cancel returns to the draft. Do not persist acknowledgement.

- [ ] **Step 7: Regenerate localization and verify**

```bash
flutter gen-l10n
flutter test test/privacy_localization_test.dart test/story_composer_controller_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit source localization and Flutter changes**

```bash
git add lib/features/onboarding/onboarding_screen.dart lib/features/privacy/privacy_review_screen.dart lib/features/privacy/privacy_notice_screen.dart lib/data/repositories/profile_repository.dart lib/data/repositories/http_profile_repository.dart lib/data/repositories/authored_story_repository.dart lib/data/repositories/http_authored_story_repository.dart lib/features/story_composer/story_composer_screen.dart lib/l10n/app_en.arb lib/l10n/app_vi.arb test/privacy_localization_test.dart test/story_composer_controller_test.dart
git commit -m "feat(privacy): add consent-first family setup"
```

---

## Slice 3: Optional Progress Tracking

### Task 10: Enforce progress consent on backend writes

**Files:**
- Modify: `backend/app/routers/sessions.py`
- Modify: `backend/tests/test_sessions.py`
- Create: `backend/tests/test_privacy_concurrency.py`

- [ ] **Step 1: Add session enforcement tests**

Test start, last-page patch, completion, and direct event writes for default-off,
enabled, revoked, and stale-policy states. Assert list sessions/events remain
readable after revocation.

- [ ] **Step 2: Add revocation concurrency test**

Use two PostgreSQL sessions and synchronization events. Hold a protected write
after acquiring the user lock, start revocation in the second session, release
the write, then assert no write commits after revocation returns.

- [ ] **Step 3: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_sessions.py tests/test_privacy_concurrency.py -v`

Expected: new disabled/concurrency cases FAIL.

- [ ] **Step 4: Protect every session mutation**

For `start_session`, `patch_session`, and `add_event`, execute lock → fetch
privacy → `require_progress` → ownership/content checks → repository write →
commit. Map failure to `403 {"detail":"progress_tracking_disabled"}`. Leave
read routes unchanged.

- [ ] **Step 5: Verify backend progress tests**

Run: `cd backend && uv run pytest tests/test_sessions.py tests/test_privacy_concurrency.py -v`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/sessions.py backend/tests/test_sessions.py backend/tests/test_privacy_concurrency.py
git commit -m "feat(privacy): enforce optional progress tracking"
```

### Task 11: Add typed session rejection and tracker

**Files:**
- Modify: `lib/data/repositories/session_repository.dart`
- Modify: `lib/data/repositories/http_session_repository.dart`
- Create: `lib/features/player/reading_session_tracker.dart`
- Create: `test/reading_session_tracker_test.dart`
- Modify: `test/http_repositories_test.dart`

- [ ] **Step 1: Add tracker unit tests**

Cover disabled startup, enabled startup, page writes, question writes,
completion, start rejection, mid-session rejection, non-consent network failure,
and permanent suppression after the first progress rejection.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/reading_session_tracker_test.dart test/http_repositories_test.dart`

Expected: FAIL because tracker and typed error do not exist.

- [ ] **Step 3: Add `SessionFailure` decoding**

```dart
class SessionFailure implements Exception {
  const SessionFailure(this.code);
  final String code;
}
```

Every HTTP session write catches `DioException`; detail
`progress_tracking_disabled` becomes that exact code. Preserve authentication,
network, and upstream codes separately.

- [ ] **Step 4: Implement the tracker**

Expose:

```dart
class ReadingSessionTracker {
  ReadingSessionTracker({required SessionRepository repository,
    required bool trackingEnabled});
  String? get sessionId;
  bool get writesDisabled;
  Future<void> start({required String childProfileId, required String storyId,
    required SessionMode mode});
  Future<void> pageViewed({required String pageId, required int pageNumber,
    String? mode});
  Future<void> questionAnswered({required String pageId,
    required String questionId, required String answerId,
    required bool isCorrect});
  Future<void> complete();
}
```

When tracking is false, methods are no-ops. Catch only
`SessionFailure('progress_tracking_disabled')` to set `writesDisabled = true`
and clear `sessionId`; rethrow other failures from `start`, but suppress
non-consent analytics failures after reading has begun so reading stays usable.

- [ ] **Step 5: Verify tracker and HTTP tests**

Run: `flutter test test/reading_session_tracker_test.dart test/http_repositories_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/session_repository.dart lib/data/repositories/http_session_repository.dart lib/features/player/reading_session_tracker.dart test/reading_session_tracker_test.dart test/http_repositories_test.dart
git commit -m "feat(privacy): centralize optional reading tracking"
```

### Task 12: Route all reader events through the tracker

**Files:**
- Modify: `lib/features/player/story_player_screen.dart`
- Modify: `lib/features/questions/question_sheet.dart`
- Modify: `lib/features/dashboard/dashboard_providers.dart`
- Modify: `lib/features/dashboard/parent_dashboard_screen.dart`
- Modify: `test/dashboard_summary_test.dart`

- [ ] **Step 1: Extend dashboard-state tests**

Define and test `trackingOffNoHistory`, `trackingOnNoHistory`,
`trackingOnWithHistory`, and `trackingOffRetainedHistory`. Preserve remote errors
as errors rather than empty history.

- [ ] **Step 2: Run dashboard tests and verify failure**

Run: `flutter test test/dashboard_summary_test.dart`

Expected: FAIL because privacy-aware states do not exist.

- [ ] **Step 3: Replace direct reader repository writes**

Construct one `ReadingSessionTracker` per `_PlayerBodyState` from effective
privacy state. Await tracker `start()` before initial tracked page handling to
remove the existing start/load race. Route normal pages, AR-return pages, and
completion through tracker methods.

- [ ] **Step 4: Inject question event callback**

Change `showPageQuestions` and `showStoryQuestions` to accept:

```dart
Future<void> Function({required String pageId, required String questionId,
  required String answerId, required bool isCorrect})? onAnswered
```

Always advance question UI. Invoke the callback when non-null; the tracker owns
whether a network write is still allowed.

- [ ] **Step 5: Add privacy-aware dashboard state**

Combine effective privacy state with readable sessions. When tracking is off,
history presence determines no-history versus retained-history. When tracking
is on, history determines empty versus active. Keep library recommendations
available in all states.

- [ ] **Step 6: Verify focused Flutter tests**

Run: `flutter test test/reading_session_tracker_test.dart test/dashboard_summary_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/player/story_player_screen.dart lib/features/questions/question_sheet.dart lib/features/dashboard/dashboard_providers.dart lib/features/dashboard/parent_dashboard_screen.dart test/dashboard_summary_test.dart
git commit -m "feat(privacy): keep reading available without tracking"
```

---

## Slice 4: Optional Cloud Narration

### Task 13: Reject cloud TTS before service construction

**Files:**
- Modify: `backend/app/routers/tts.py`
- Modify: `backend/tests/test_tts.py`

- [ ] **Step 1: Add construction-order tests**

Override the OpenAI service factory with a counter/throwing fake. Assert default,
revoked, and stale consent return `403 cloud_tts_disabled` while construction
and generation counts remain zero. Assert enabled consent constructs once.

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_tts.py -v`

Expected: disabled cases FAIL because service dependency resolves first.

- [ ] **Step 3: Resolve the service after privacy check**

Remove `service: OpenAiTtsService = Depends(get_tts_service)` from the route.
Inject `db` and authenticated `user`, check effective cloud consent, then call
`get_tts_service()` inside the route body. Do not hold the database lock during
the external OpenAI call; consent is authoritative at request start for TTS.

- [ ] **Step 4: Verify TTS tests**

Run: `cd backend && uv run pytest tests/test_tts.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/routers/tts.py backend/tests/test_tts.py
git commit -m "feat(privacy): gate cloud narration before OpenAI"
```

### Task 14: Add device Scan Any Page narration and source selection

**Files:**
- Create: `lib/features/scan_any_page/device_tts_client.dart`
- Create: `lib/features/player/narration_source_selection.dart`
- Modify: `lib/features/scan_any_page/tts_client.dart`
- Create: `test/device_tts_client_test.dart`
- Create: `test/narration_source_selection_test.dart`
- Modify: `test/tts_client_test.dart`

- [ ] **Step 1: Add failing source-selection tests**

Test effective consent false, true, consent rejection, network failure, invalid
text, generated extension, and disposal. Assert disabled selection never calls
the HTTP fake.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/device_tts_client_test.dart test/narration_source_selection_test.dart test/tts_client_test.dart`

Expected: FAIL because device adapter/selection do not exist.

- [ ] **Step 3: Add typed cloud-TTS failure**

Update `HttpTtsClient` so FastAPI detail `cloud_tts_disabled` maps to
`TtsGenerationFailure('cloud_tts_disabled')`, before status-based 401/403
authentication mapping.

- [ ] **Step 4: Implement `DeviceTtsClient`**

Adapt `TtsFileSynthesizer` to `TtsClient`. Resolve an injected directory, create
the requested filename using the synthesizer's extension, call
`synthesizeToFile`, return the file only on success, and delete owned generated
files during `dispose()`.

- [ ] **Step 5: Implement source selection**

Create a small factory that returns device-only when effective consent is false,
and a cloud-first wrapper when true. The wrapper catches cloud consent/network/
upstream generation failures and calls the device client; it does not catch
input validation before generation.

- [ ] **Step 6: Verify narration source tests**

Run: `flutter test test/device_tts_client_test.dart test/narration_source_selection_test.dart test/tts_client_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/scan_any_page/device_tts_client.dart lib/features/player/narration_source_selection.dart lib/features/scan_any_page/tts_client.dart test/device_tts_client_test.dart test/narration_source_selection_test.dart test/tts_client_test.dart
git commit -m "feat(privacy): add on-device scan narration"
```

### Task 15: Wire narration choice through player, scan, and AR

**Files:**
- Modify: `lib/core/di.dart`
- Modify: `lib/features/scan_any_page/scan_any_page_screen.dart`
- Modify: `lib/features/scan_any_page/scan_any_page_controller.dart`
- Modify: `lib/features/player/story_player_screen.dart`
- Modify: `lib/features/player/narration_audio_fetcher.dart`
- Modify: `lib/features/player/narration_player.dart`
- Modify: `lib/features/ar/ar_narration_bundle.dart`
- Modify: `lib/features/ar/ar_narration_sources.dart`
- Modify: `test/scan_any_page_controller_test.dart`
- Modify: `test/narration_audio_fetcher_test.dart`
- Modify: `test/narration_player_test.dart`
- Modify: `test/ar_narration_bundle_test.dart`
- Modify: `test/ar_reader_controller_test.dart`

- [ ] **Step 1: Add no-HTTP and fallback tests**

Assert authored player and Scan Any Page construct no HTTP client when consent is
false. Assert consent rejection falls back to device audio. Assert AR receives
`fetcher == null` when cloud is disabled and still synthesizes each segment.

- [ ] **Step 2: Run focused narration tests and verify failure**

Run:

```bash
flutter test test/scan_any_page_controller_test.dart test/narration_audio_fetcher_test.dart test/narration_player_test.dart test/ar_narration_bundle_test.dart test/ar_reader_controller_test.dart
```

Expected: new no-HTTP cases FAIL.

- [ ] **Step 3: Make DI consent-aware per operation**

Read effective cloud consent when constructing each authored fetcher or scan
flow. Disabled authored stories pass no HTTP fetcher to `NarrationPlayer` and
AR. Scan flows receive the selected device-only/cloud-first `TtsClient`.

- [ ] **Step 4: Preserve fallback behavior**

Keep curated registered clips first, authored cloud fetch second only when
enabled, and `FlutterTtsFileSynthesizer` last for AR. Preference changes affect
the next newly constructed operation; do not interrupt active audio.

- [ ] **Step 5: Verify narration regressions**

Run the same focused command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/di.dart lib/features/scan_any_page/scan_any_page_screen.dart lib/features/scan_any_page/scan_any_page_controller.dart lib/features/player/story_player_screen.dart lib/features/player/narration_audio_fetcher.dart lib/features/player/narration_player.dart lib/features/ar/ar_narration_bundle.dart lib/features/ar/ar_narration_sources.dart test/scan_any_page_controller_test.dart test/narration_audio_fetcher_test.dart test/narration_player_test.dart test/ar_narration_bundle_test.dart test/ar_reader_controller_test.dart
git commit -m "feat(privacy): apply optional narration across readers"
```

---

## Slice 5: Parent Privacy Management

### Task 16: Add reading-history deletion backend

**Files:**
- Modify: `backend/app/repositories/privacy.py`
- Modify: `backend/app/services/privacy.py`
- Modify: `backend/app/routers/privacy.py`
- Create: `backend/tests/test_privacy_history_deletion.py`

- [ ] **Step 1: Add populated deletion tests**

Create curated and authored story sessions/events for owned profiles. Assert
events and sessions delete, while profiles, authored content, settings, and
consent events remain. Assert repeated deletion returns 204 and rollback keeps
all history.

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_history_deletion.py -v`

Expected: FAIL with 404 endpoint.

- [ ] **Step 3: Implement locked history deletion**

Under the user lock, select session IDs where the session belongs to an owned
profile or references a user-authored story. Delete `InteractionEvent` rows
first, then `StorySession` rows, flush, and let the route commit. Return 204 even
when no rows exist.

- [ ] **Step 4: Verify history deletion tests**

Run: `cd backend && uv run pytest tests/test_privacy_history_deletion.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/repositories/privacy.py backend/app/services/privacy.py backend/app/routers/privacy.py backend/tests/test_privacy_history_deletion.py
git commit -m "feat(privacy): add reading history deletion"
```

### Task 17: Add parent Privacy & Data controls

**Files:**
- Create: `lib/features/privacy/privacy_screen.dart`
- Modify: `lib/features/privacy/privacy_providers.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/features/dashboard/dashboard_providers.dart`
- Modify: `lib/features/dashboard/parent_dashboard_screen.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_vi.arb`
- Create: `test/privacy_notifier_test.dart`
- Modify: `test/dashboard_summary_test.dart`

- [ ] **Step 1: Add notifier sequencing tests**

Assert option updates serialize, server responses replace local state, tracking
is disabled before history-choice handling begins, dismissal retains history,
deletion failure retains history, and retry succeeds.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/privacy_notifier_test.dart test/dashboard_summary_test.dart`

Expected: FAIL because parent operations/states do not exist.

- [ ] **Step 3: Implement notifier operations**

Add `setProgressTracking`, `setCloudTts`, `deleteReadingHistory`, and
`deleteChildData` methods. Each PUT resends the complete current-policy body.
`setProgressTracking(false)` awaits server state before the UI opens the
retain/delete dialog.

- [ ] **Step 4: Implement `/parent/privacy` screen**

Render policy version/date, four stored-data counts, optional switches,
retained-history action, link to `/privacy-notice`, 90-day inactivity statement,
and destructive full-deletion entry. Full deletion requires a second dialog
whose title and body explicitly say that profile, authored stories, reading
history, and privacy choices will be permanently deleted; only its destructive
button invokes `deleteChildData()`. Use the existing parental gate through the
`/parent` prefix.

- [ ] **Step 5: Link settings and update dashboard states**

Replace the static privacy card with accurate summary copy and navigation.
Render tracking-off/empty/active/retained states without claiming remote errors
mean no history.

- [ ] **Step 6: Generate localization and verify**

```bash
flutter gen-l10n
flutter test test/privacy_notifier_test.dart test/dashboard_summary_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/privacy/privacy_screen.dart lib/features/privacy/privacy_providers.dart lib/core/router/app_router.dart lib/features/settings/settings_screen.dart lib/features/dashboard/dashboard_providers.dart lib/features/dashboard/parent_dashboard_screen.dart lib/l10n/app_en.arb lib/l10n/app_vi.arb test/privacy_notifier_test.dart test/dashboard_summary_test.dart
git commit -m "feat(privacy): add parent data controls"
```

---

## Slice 6: Full Child-Data Deletion and Recovery

### Task 18: Add shared backend child-data deletion service

**Files:**
- Create: `backend/app/services/child_data_deletion.py`
- Modify: `backend/app/routers/privacy.py`
- Modify: `backend/app/services/privacy.py`
- Create: `backend/tests/test_child_data_deletion.py`
- Modify: `backend/tests/test_privacy_concurrency.py`

- [ ] **Step 1: Add fully populated deletion tests**

Populate profile, authored story, pages, segments, AR scenes, questions,
choices, sessions, events, consent events, and settings. Assert deletion order,
atomic rollback, idempotency, retained user/device, successful reauthentication,
and empty-row recreation on next privacy GET.

- [ ] **Step 2: Add concurrent protected-write cases**

For profile, authored story, session, and event writes, prove no transaction
that began under the old state commits after full deletion returns.

- [ ] **Step 3: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_child_data_deletion.py tests/test_privacy_concurrency.py -v`

Expected: FAIL because deletion service/endpoint do not exist.

- [ ] **Step 4: Implement explicit FK-safe deletion**

Expose `delete_child_data(db: Session, user_id: str) -> None`. It performs no
commit and deletes in this exact order: events, sessions, authored-story
question choices, authored questions/scenes/segments/pages, authored stories,
profiles, consent events, privacy settings. Preserve user/device rows.

- [ ] **Step 5: Add the endpoint and row recreation**

`DELETE /v1/privacy/child-data` locks `users`, calls the service, commits, and
returns 204. `GET /v1/privacy` locks the retained user and creates a fresh null
policy/off row if missing.

- [ ] **Step 6: Verify deletion/concurrency tests**

Run the same focused command from Step 3.

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/services/child_data_deletion.py backend/app/routers/privacy.py backend/app/services/privacy.py backend/tests/test_child_data_deletion.py backend/tests/test_privacy_concurrency.py
git commit -m "feat(privacy): delete all child data atomically"
```

### Task 19: Centralize local persistence keys

**Files:**
- Create: `lib/data/sources/persistence_keys.dart`
- Modify: `lib/data/sources/api_client.dart`
- Modify: `lib/data/repositories/profile_repository.dart`
- Modify: `lib/data/repositories/session_repository.dart`
- Modify: `lib/data/repositories/settings_repository.dart`
- Modify: `lib/features/settings/settings_providers.dart`
- Modify: `lib/features/settings/locale_providers.dart`
- Modify: `lib/features/ar/ar_character_providers.dart`
- Modify: `lib/data/sources/key_value_store.dart`
- Create: `test/persistence_keys_test.dart`

- [ ] **Step 1: Add registry completeness tests**

Assert exact sets and no overlap:

```dart
const preservedKeys = {
  'device_id', 'device_secret', 'auth_user_id', 'auth_token',
  'ui_locale_override',
};
const childDataKeys = {
  'parent_consent', 'child_profile', 'story_sessions', 'interaction_events',
  'reading_settings', 'settings_daily_limit_minutes',
  'settings_content_filter_band', 'settings_notifications_enabled',
  'ar.selected_character_id', 'privacy_state_cache',
  'privacy_activity_last_utc_date',
};
const cleanupPendingKey = 'child_cleanup_pending';
```

Test `allKnownKeys == preservedKeys ∪ childDataKeys ∪ {cleanupPendingKey}`.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/persistence_keys_test.dart`

Expected: FAIL because registry does not exist.

- [ ] **Step 3: Create registry and consume constants**

Move every existing private key literal to named constants in
`persistence_keys.dart`. Keep the legacy keys even after local consent logic is
removed so deletion clears old installations.

- [ ] **Step 4: Add minimal store inspection**

Expose `Set<String> get keys => _prefs.getKeys();` and retain existing
single-key `remove`. Do not add arbitrary bulk-clearing that could erase
preserved credentials.

- [ ] **Step 5: Verify registry tests and regressions**

Run: `flutter test test/persistence_keys_test.dart test/http_repositories_test.dart test/dashboard_summary_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/sources/persistence_keys.dart lib/data/sources/api_client.dart lib/data/repositories/profile_repository.dart lib/data/repositories/session_repository.dart lib/data/repositories/settings_repository.dart lib/features/settings/settings_providers.dart lib/features/settings/locale_providers.dart lib/features/ar/ar_character_providers.dart lib/data/sources/key_value_store.dart test/persistence_keys_test.dart
git commit -m "refactor(privacy): centralize persisted data keys"
```

### Task 20: Add ordered local cleanup and bootstrap repair

**Files:**
- Create: `lib/features/privacy/child_data_cleaner.dart`
- Modify: `lib/features/privacy/privacy_providers.dart`
- Modify: `lib/core/di.dart`
- Modify: `lib/main.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/player/narration_audio_fetcher.dart`
- Modify: `lib/features/scan_any_page/scan_any_page_controller.dart`
- Modify: `lib/features/ar/ar_reader_controller.dart`
- Create: `test/child_data_cleaner_test.dart`
- Modify: `test/narration_audio_fetcher_test.dart`
- Modify: `test/scan_any_page_controller_test.dart`
- Modify: `test/ar_reader_controller_test.dart`

- [ ] **Step 1: Add cleanup tests with isolated directories**

Test server-failure no-op, marker-first ordering, preserved keys, every child key,
provider invalidation callback, exact owned file patterns, unrelated file
preservation, interruption with marker retained, and successful bootstrap retry.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/child_data_cleaner_test.dart`

Expected: FAIL because cleaner does not exist.

- [ ] **Step 3: Implement `ChildDataCleaner`**

Inject `KeyValueStore`, explicit cache/temp directories, a list of async
resource disposers, and one provider-invalidation callback. `clean()` performs:

```dart
await store.setBool(cleanupPendingKey, true);
for (final dispose in disposers) await dispose();
for (final key in childDataKeys) await store.remove(key);
await deleteOwnedAudioFiles(directories);
invalidateProviders();
await store.remove(cleanupPendingKey);
```

Match `scan_any_page_narration` with mp3/caf/wav and temporary forms,
`narration_*.mp3`, and `ar_*_p*_s*` with mp3/caf/wav and temporary forms. Iterate
only direct files in injected app-owned directories; never recursively delete a
system temp directory.

- [ ] **Step 4: Expose explicit resource disposal**

Ensure narration fetchers, scan clients/controllers, and AR preparation
controllers can be disposed/cancelled through owned providers or registered
callbacks before file deletion. Do not add a global media manager.

- [ ] **Step 5: Wire full deletion and bootstrap repair**

Privacy notifier calls server deletion first. Only after 204 does it invoke the
cleaner. At startup, a remaining marker invokes cleanup before access routing.
If server state is a fresh null-policy row with no profile after deletion but
the marker was never written, bootstrap also runs cleanup when any registered
child key or owned generated-audio file remains.
After cleanup, invalidate privacy, profile, dashboard, library/detail, settings,
safety settings, selected character, scan, narration, and access/router state.

- [ ] **Step 6: Verify cleanup and resource tests**

Run:

```bash
flutter test test/child_data_cleaner_test.dart test/narration_audio_fetcher_test.dart test/scan_any_page_controller_test.dart test/ar_reader_controller_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/privacy/child_data_cleaner.dart lib/features/privacy/privacy_providers.dart lib/core/di.dart lib/main.dart lib/core/router/app_router.dart lib/features/player/narration_audio_fetcher.dart lib/features/scan_any_page/scan_any_page_controller.dart lib/features/ar/ar_reader_controller.dart test/child_data_cleaner_test.dart test/narration_audio_fetcher_test.dart test/scan_any_page_controller_test.dart test/ar_reader_controller_test.dart
git commit -m "feat(privacy): repair local state after child deletion"
```

---

## Slice 7: Activity Retention and Release Readiness

### Task 21: Add backend activity tracking

**Files:**
- Modify: `backend/app/repositories/privacy.py`
- Modify: `backend/app/services/privacy.py`
- Modify: `backend/app/routers/privacy.py`
- Modify: `backend/app/auth.py`
- Create: `backend/tests/test_privacy_activity.py`

- [ ] **Step 1: Add activity endpoint and auth-touch tests**

Use an injected clock. Test explicit endpoint, same-UTC-date throttle, next-date
update, successful authenticated legacy request, and no row recreation after
full deletion except through privacy GET.

- [ ] **Step 2: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_activity.py -v`

Expected: FAIL because activity behavior does not exist.

- [ ] **Step 3: Implement throttled touch**

Expose:

```python
def touch_activity_if_due(db: Session, user_id: str, now: datetime) -> bool:
    settings = privacy_repo.get_settings(db, user_id)
    if settings is None or settings.last_active_at.astimezone(timezone.utc).date() >= now.date():
        return False
    settings.last_active_at = now
    settings.updated_at = now
    db.flush()
    return True
```

The explicit endpoint commits when changed and returns 204. In
`get_current_user`, touch an existing row and commit the touch before returning
the authenticated user; never create a missing row there.

- [ ] **Step 4: Verify activity tests**

Run: `cd backend && uv run pytest tests/test_privacy_activity.py -v`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/app/repositories/privacy.py backend/app/services/privacy.py backend/app/routers/privacy.py backend/app/auth.py backend/tests/test_privacy_activity.py
git commit -m "feat(privacy): track active family accounts"
```

### Task 22: Add Flutter foreground activity throttle

**Files:**
- Create: `lib/features/privacy/privacy_activity_notifier.dart`
- Modify: `lib/app.dart`
- Modify: `lib/features/privacy/privacy_providers.dart`
- Modify: `lib/data/repositories/privacy_repository.dart`
- Modify: `lib/data/repositories/http_privacy_repository.dart`
- Modify: `lib/data/sources/persistence_keys.dart`
- Create: `test/privacy_activity_notifier_test.dart`
- Modify: `test/http_repositories_test.dart`
- Modify: `test/child_data_cleaner_test.dart`

- [ ] **Step 1: Add lifecycle/throttle unit tests**

Inject a UTC clock. Assert first foreground sends, repeated same date skips,
next UTC date sends, network failure does not alter access state, and full
deletion clears the throttle key.

- [ ] **Step 2: Run and verify failure**

Run: `flutter test test/privacy_activity_notifier_test.dart test/http_repositories_test.dart test/child_data_cleaner_test.dart`

Expected: FAIL because notifier does not exist.

- [ ] **Step 3: Implement notifier**

Expose `Future<void> onForeground()` that compares today's UTC `yyyy-MM-dd`
with `privacyActivityLastUtcDateKey`, calls repository activity, and writes the
key only after success. Catch failures without changing privacy/access state.

- [ ] **Step 4: Attach app lifecycle**

Use a small `ConsumerStatefulWidget` app root with `WidgetsBindingObserver`.
Call foreground activity for `AppLifecycleState.resumed` only. Do not send on
inactive, paused, hidden, or detached.

- [ ] **Step 5: Verify activity tests**

Run the same focused command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/privacy/privacy_activity_notifier.dart lib/app.dart lib/features/privacy/privacy_providers.dart lib/data/repositories/privacy_repository.dart lib/data/repositories/http_privacy_repository.dart lib/data/sources/persistence_keys.dart test/privacy_activity_notifier_test.dart test/http_repositories_test.dart test/child_data_cleaner_test.dart
git commit -m "feat(privacy): report daily foreground activity"
```

### Task 23: Add retention and reconciliation commands

**Files:**
- Create: `backend/privacy_retention.py`
- Create: `backend/privacy_reconcile.py`
- Modify: `backend/app/repositories/privacy.py`
- Create: `backend/tests/test_privacy_retention.py`
- Create: `backend/tests/test_privacy_reconcile.py`

- [ ] **Step 1: Add retention boundary tests**

Test strictly older than 90 days, exact boundary skipped, profiles and authored
stories as owner signals, dry run, lock-time activity recheck, idempotent retry,
one-user failure continuation, and use of shared deletion service.

- [ ] **Step 2: Add reconciliation tests**

Test insertion for missing rows, preservation of existing consent, idempotency,
and exact one-row-per-user result.

- [ ] **Step 3: Run and verify failure**

Run: `cd backend && uv run pytest tests/test_privacy_retention.py tests/test_privacy_reconcile.py -v`

Expected: FAIL because commands do not exist.

- [ ] **Step 4: Implement retention CLI**

Use `argparse` with only `--dry-run`. Calculate `cutoff = now - timedelta(days=90)`
and select owners with profile or authored story and `last_active_at < cutoff`.
For each user open an independent session, lock user, re-read activity, skip if
no longer eligible, call shared deletion service, and commit. Print only:

```text
attempted=<n> deleted=<n> skipped=<n> failed=<n> dry_run=<true|false>
```

Exit 0 when all attempts succeed or skip; exit 1 when `failed > 0`.

- [ ] **Step 5: Implement reconciliation CLI**

Insert default rows for missing users in one transaction, verify
`count(users) == count(privacy_settings)`, print
`created=<n> users=<n> privacy_rows=<n>`, and exit nonzero if counts differ.

- [ ] **Step 6: Verify command tests**

Run: `cd backend && uv run pytest tests/test_privacy_retention.py tests/test_privacy_reconcile.py -v`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/privacy_retention.py backend/privacy_reconcile.py backend/app/repositories/privacy.py backend/tests/test_privacy_retention.py backend/tests/test_privacy_reconcile.py
git commit -m "feat(privacy): add retention and reconciliation commands"
```

### Task 24: Make production startup compatible with coordinated maintenance

**Files:**
- Modify: `backend/deploy/entrypoint.sh`
- Modify: `backend/deploy/deploy.sh`
- Modify: `backend/deploy/docker-compose.prod.yml`
- Modify: `backend/deploy/README.md`

- [ ] **Step 1: Remove automatic migration from API entrypoint**

Make `entrypoint.sh` start Uvicorn only. Migration and reconciliation are
explicit maintenance commands so an API restart cannot bypass the coordinated
sequence.

- [ ] **Step 2: Split deployment into explicit commands**

Update `deploy.sh` to require one action:

```text
./deploy.sh build
./deploy.sh maintenance-up
./deploy.sh migrate
./deploy.sh api-up
./deploy.sh reconcile
./deploy.sh verify-internal
./deploy.sh traffic-up
```

`maintenance-up` stops Caddy/API while keeping DB running. `migrate` runs
`alembic upgrade head` in a one-off API container. `reconcile` runs
`privacy_reconcile.py`. `api-up` starts only the API on the internal Compose
network. `verify-internal` checks API health and reruns the exact-one-row
verification while Caddy remains stopped. `traffic-up` starts Caddy only after
verification passes. Keep initial secret validation for every action.

- [ ] **Step 3: Document the roll-forward sequence**

Document exact order: maintenance → build → migrate/backfill → start backend →
reconcile/verify before Caddy traffic → resume API traffic → release Flutter →
retention dry run → enable daily retention. State that after enforcement begins
the safe response is maintenance plus roll-forward, not old-backend rollback.

- [ ] **Step 4: Validate shell and Compose syntax without deploying**

Run:

```bash
bash -n backend/deploy/deploy.sh
sh -n backend/deploy/entrypoint.sh
docker compose -f backend/deploy/docker-compose.prod.yml config --quiet
```

Expected: all commands exit 0. Do not run any deploy action.

- [ ] **Step 5: Commit**

```bash
git add backend/deploy/entrypoint.sh backend/deploy/deploy.sh backend/deploy/docker-compose.prod.yml backend/deploy/README.md
git commit -m "docs(privacy): add coordinated release controls"
```

---

## Final Verification

### Task 25: Run focused regression suites and close the work item

**Files:**
- Modify after all verification passes: `docs/REMAINING_WORK.md`

- [ ] **Step 1: Run focused backend privacy tests**

```bash
cd backend && uv run pytest \
  tests/test_privacy_migration.py \
  tests/test_privacy_foundation.py \
  tests/test_privacy_api.py \
  tests/test_privacy_concurrency.py \
  tests/test_privacy_history_deletion.py \
  tests/test_child_data_deletion.py \
  tests/test_privacy_activity.py \
  tests/test_privacy_retention.py \
  tests/test_privacy_reconcile.py \
  tests/test_auth.py \
  tests/test_profiles.py \
  tests/test_authored_stories.py \
  tests/test_sessions.py \
  tests/test_tts.py -v
```

Expected: PASS.

- [ ] **Step 2: Run the complete backend regression suite**

Run: `cd backend && uv run pytest -q`

Expected: exit 0.

- [ ] **Step 3: Run focused Flutter privacy and media tests**

```bash
flutter test \
  test/http_repositories_test.dart \
  test/privacy_providers_test.dart \
  test/app_access_state_test.dart \
  test/privacy_localization_test.dart \
  test/reading_session_tracker_test.dart \
  test/dashboard_summary_test.dart \
  test/narration_source_selection_test.dart \
  test/device_tts_client_test.dart \
  test/tts_client_test.dart \
  test/scan_any_page_controller_test.dart \
  test/narration_audio_fetcher_test.dart \
  test/narration_player_test.dart \
  test/ar_narration_bundle_test.dart \
  test/ar_reader_controller_test.dart \
  test/privacy_notifier_test.dart \
  test/persistence_keys_test.dart \
  test/child_data_cleaner_test.dart \
  test/privacy_activity_notifier_test.dart
```

Expected: PASS. Do not include `test/widget_test.dart`.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze`

Expected: exit 0 with no analyzer errors.

- [ ] **Step 5: Verify copy and persistence claims**

Run literal searches and confirm zero inaccurate user-facing claims:

```bash
rg -n -i "stored only on (this|the) device|chỉ được lưu trên thiết bị" lib/l10n
rg -n "parent_consent|child_profile|story_sessions|interaction_events|reading_settings|settings_daily_limit_minutes|settings_content_filter_band|settings_notifications_enabled|ar.selected_character_id" lib --glob '*.dart'
```

Expected: first command has no matches. Every second-command key occurrence is
the central registry, a generated/reference test, or a documented legacy reader
using the registry constant; no private duplicate literals remain.

- [ ] **Step 6: Mark the P0 work item complete**

Only after Steps 1-5 pass, change the first checkbox in
`docs/REMAINING_WORK.md` from `[ ]` to `[x]`. Do not mark physical-device,
VoiceOver, TalkBack, migration execution, deployment, or retention-job
activation complete; those require separate explicit approval and execution.

- [ ] **Step 7: Commit verification closure**

```bash
git add docs/REMAINING_WORK.md
git commit -m "docs(privacy): mark implementation complete"
```

## Post-Implementation Manual Gates

These are not executed by this plan:

1. Review the generated English and Vietnamese privacy notice with the product
   owner and legal/privacy adviser.
2. Exercise new-family setup, declined optional choices, policy review, retained
   history, history deletion, and full deletion on physical iOS and Android.
3. Verify VoiceOver and TalkBack on onboarding, review, notice, and parent
   privacy controls with increased text size.
4. Rehearse the maintenance, migration, reconciliation, roll-forward, and
   retention dry-run procedure against a production-like backup.
5. Obtain explicit in-session approval before running migrations, deploying,
   enabling retention mutations, or publishing the Flutter build.
