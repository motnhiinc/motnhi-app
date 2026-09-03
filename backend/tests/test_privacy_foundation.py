from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.exc import OperationalError

from app.models import (
    ChildProfile,
    ConsentEvent,
    InteractionEvent,
    PrivacySettings,
    Story,
    StorySession,
    User,
)
from app.repositories import privacy as privacy_repo
from app.services import privacy


def _add_user(db, user_id: str, now: datetime) -> None:
    db.add(User(
        id=user_id,
        email=None,
        auth_provider="device",
        created_at=now,
        updated_at=now,
    ))
    # Flush parent rows immediately: with no ORM relationship between User and
    # its dependents, the unit of work orders per-mapper inserts alphabetically
    # by class name (ChildProfile < User), not by FK dependency.
    db.flush()


def _add_profile(db, profile_id: str, user_id: str, now: datetime) -> None:
    db.add(ChildProfile(
        id=profile_id,
        user_id=user_id,
        nickname=None,
        age_band="3-4",
        language_code="en",
        bedtime_mode_default=False,
        microphone_enabled=False,
        ar_enabled=True,
        created_at=now,
        updated_at=now,
    ))


def _add_story(db, story_id: str, owner_user_id: str | None) -> None:
    db.add(Story(
        id=story_id,
        title=story_id,
        slug=story_id,
        description=None,
        age_min=3,
        age_max=8,
        language_code="en",
        duration_seconds=60,
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=owner_user_id,
    ))


def _add_session_with_event(
    db,
    session_id: str,
    profile_id: str,
    story_id: str,
    now: datetime,
) -> None:
    db.add(StorySession(
        id=session_id,
        child_profile_id=profile_id,
        story_id=story_id,
        started_at=now,
        completed_at=None,
        last_page_number=0,
        mode="library",
    ))
    db.flush()
    db.add(InteractionEvent(
        id=f"event-{session_id}",
        story_session_id=session_id,
        event_type="story_started",
        page_id=None,
        payload={},
        created_at=now,
    ))


def _add_privacy_settings(
    db,
    user_id: str,
    last_active_at: datetime,
) -> PrivacySettings:
    settings = PrivacySettings(
        user_id=user_id,
        accepted_policy_version=None,
        core_storage_accepted_at=None,
        progress_tracking_enabled=False,
        cloud_tts_enabled=False,
        last_active_at=last_active_at,
        updated_at=last_active_at,
    )
    db.add(settings)
    return settings


def test_effective_choices_require_current_policy():
    now = datetime.now(timezone.utc)
    settings = PrivacySettings(
        user_id="effective-user",
        accepted_policy_version="old-policy",
        core_storage_accepted_at=now,
        progress_tracking_enabled=True,
        cloud_tts_enabled=True,
        last_active_at=now,
        updated_at=now,
    )

    assert privacy.effective_progress(settings) is False
    assert privacy.effective_cloud_tts(settings) is False

    settings.accepted_policy_version = privacy.CURRENT_PRIVACY_POLICY_VERSION

    assert privacy.effective_progress(settings) is True
    assert privacy.effective_cloud_tts(settings) is True


def test_lock_user_uses_retained_user_row(independent_session_factory):
    owner = independent_session_factory(user_id="retained-user")
    contender = independent_session_factory()

    locked = privacy.lock_user(owner, "retained-user")

    assert locked.id == "retained-user"
    assert owner.get(PrivacySettings, "retained-user") is None
    with pytest.raises(OperationalError):
        contender.scalar(
            select(User)
            .where(User.id == "retained-user")
            .with_for_update(nowait=True)
        )


def test_update_appends_all_scopes_on_first_acceptance(
    independent_session_factory,
):
    db = independent_session_factory(user_id="first-acceptance-user")

    settings = privacy.update_settings(
        db,
        "first-acceptance-user",
        policy_version=privacy.CURRENT_PRIVACY_POLICY_VERSION,
        core_storage_accepted=True,
        progress_tracking_enabled=False,
        cloud_tts_enabled=True,
    )
    events = list(db.scalars(
        select(ConsentEvent).where(ConsentEvent.user_id == "first-acceptance-user")
    ))

    assert settings.accepted_policy_version == privacy.CURRENT_PRIVACY_POLICY_VERSION
    assert settings.core_storage_accepted_at is not None
    assert len(events) == 3
    assert {event.scope for event in events} == {
        "core_storage",
        "progress_tracking",
        "cloud_tts",
    }
    assert {event.scope: event.granted for event in events} == {
        "core_storage": True,
        "progress_tracking": False,
        "cloud_tts": True,
    }


def test_repeated_update_appends_only_changed_scope(
    independent_session_factory,
):
    db = independent_session_factory(user_id="repeated-update-user")
    first = privacy.update_settings(
        db,
        "repeated-update-user",
        policy_version=privacy.CURRENT_PRIVACY_POLICY_VERSION,
        core_storage_accepted=True,
        progress_tracking_enabled=False,
        cloud_tts_enabled=False,
    )
    first_accepted_at = first.core_storage_accepted_at
    initial_event_ids = set(db.scalars(
        select(ConsentEvent.id).where(
            ConsentEvent.user_id == "repeated-update-user"
        )
    ))

    updated = privacy.update_settings(
        db,
        "repeated-update-user",
        policy_version=privacy.CURRENT_PRIVACY_POLICY_VERSION,
        core_storage_accepted=True,
        progress_tracking_enabled=True,
        cloud_tts_enabled=False,
    )
    appended_events = list(db.scalars(
        select(ConsentEvent).where(
            ConsentEvent.user_id == "repeated-update-user",
            ConsentEvent.id.not_in(initial_event_ids),
        )
    ))

    assert updated.core_storage_accepted_at == first_accepted_at
    assert len(initial_event_ids) == 3
    assert len(appended_events) == 1
    assert appended_events[0].scope == "progress_tracking"
    assert appended_events[0].granted is True


def test_update_and_events_roll_back_together(independent_session_factory):
    writer = independent_session_factory(user_id="rollback-user")
    verifier = independent_session_factory()

    privacy.update_settings(
        writer,
        "rollback-user",
        policy_version=privacy.CURRENT_PRIVACY_POLICY_VERSION,
        core_storage_accepted=True,
        progress_tracking_enabled=True,
        cloud_tts_enabled=True,
    )
    writer.rollback()

    assert verifier.get(PrivacySettings, "rollback-user") is None
    assert list(verifier.scalars(
        select(ConsentEvent).where(ConsentEvent.user_id == "rollback-user")
    )) == []


def test_data_counts_include_either_ownership_path(db):
    now = datetime.now(timezone.utc)
    _add_user(db, "counts-owner", now)
    _add_user(db, "counts-other", now)
    _add_profile(db, "counts-owner-profile", "counts-owner", now)
    _add_profile(db, "counts-other-profile", "counts-other", now)
    _add_story(db, "counts-curated-story", None)
    _add_story(db, "counts-authored-story", "counts-owner")
    _add_session_with_event(
        db,
        "counts-profile-session",
        "counts-owner-profile",
        "counts-curated-story",
        now,
    )
    _add_session_with_event(
        db,
        "counts-story-session",
        "counts-other-profile",
        "counts-authored-story",
        now,
    )
    db.flush()

    assert privacy_repo.data_counts(db, "counts-owner") == {
        "child_profiles": 1,
        "authored_stories": 1,
        "story_sessions": 2,
        "interaction_events": 2,
    }


def test_data_counts_are_distinct_when_both_ownership_paths_match(db):
    now = datetime.now(timezone.utc)
    _add_user(db, "distinct-owner", now)
    _add_profile(db, "distinct-profile", "distinct-owner", now)
    _add_story(db, "distinct-story", "distinct-owner")
    _add_session_with_event(
        db,
        "distinct-session",
        "distinct-profile",
        "distinct-story",
        now,
    )
    db.flush()

    counts = privacy_repo.data_counts(db, "distinct-owner")

    assert counts["story_sessions"] == 1
    assert counts["interaction_events"] == 1


def test_retention_candidates_require_owned_data_and_strict_cutoff(db):
    cutoff = datetime(2026, 9, 1, tzinfo=timezone.utc)
    stale = cutoff - timedelta(seconds=1)
    recent = cutoff + timedelta(seconds=1)
    user_ids = {
        "retention-stale-profile",
        "retention-stale-story",
        "retention-stale-empty",
        "retention-at-cutoff",
        "retention-recent-story",
    }
    for user_id in user_ids:
        _add_user(db, user_id, cutoff)
    _add_privacy_settings(db, "retention-stale-profile", stale)
    _add_privacy_settings(db, "retention-stale-story", stale)
    _add_privacy_settings(db, "retention-stale-empty", stale)
    _add_privacy_settings(db, "retention-at-cutoff", cutoff)
    _add_privacy_settings(db, "retention-recent-story", recent)
    _add_profile(
        db,
        "retention-stale-profile-data",
        "retention-stale-profile",
        cutoff,
    )
    _add_profile(
        db,
        "retention-at-cutoff-data",
        "retention-at-cutoff",
        cutoff,
    )
    _add_story(db, "retention-stale-story-data", "retention-stale-story")
    _add_story(db, "retention-recent-story-data", "retention-recent-story")
    db.flush()

    assert set(privacy_repo.retention_candidate_ids(db, cutoff)) == {
        "retention-stale-profile",
        "retention-stale-story",
    }


def test_missing_privacy_user_ids_preserve_existing_settings(db):
    now = datetime.now(timezone.utc)
    _add_user(db, "privacy-existing", now)
    _add_user(db, "privacy-missing-one", now)
    _add_user(db, "privacy-missing-two", now)
    existing = _add_privacy_settings(db, "privacy-existing", now)
    db.flush()

    missing = privacy_repo.missing_privacy_user_ids(db)

    assert set(missing) == {"privacy-missing-one", "privacy-missing-two"}
    assert db.get(PrivacySettings, "privacy-existing") is existing
