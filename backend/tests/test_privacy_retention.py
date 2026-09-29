from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

import privacy_retention
from app.models import ChildProfile, PrivacySettings, Story, User
from app.services import child_data_deletion
from app.services import privacy as privacy_service
from tests.conftest import TestingSessionLocal

NOW = datetime(2026, 9, 3, 12, 0, 0, tzinfo=timezone.utc)
CUTOFF = NOW - timedelta(days=privacy_retention.RETENTION_DAYS)


@pytest.fixture
def session_factory(db):
    def create():
        return TestingSessionLocal(bind=db.get_bind())

    return create


def _add_user(db, user_id, last_active_at):
    # No ORM relationship links users and privacy_settings, so the unit of
    # work will not order INSERTs across them: flush the user first.
    db.add(User(
        id=user_id,
        email=None,
        auth_provider="device",
        created_at=NOW,
        updated_at=NOW,
    ))
    db.flush()
    db.add(PrivacySettings(
        user_id=user_id,
        accepted_policy_version=None,
        core_storage_accepted_at=None,
        progress_tracking_enabled=False,
        cloud_tts_enabled=False,
        page_image_validation_enabled=False,
        last_active_at=last_active_at,
        updated_at=NOW,
    ))
    db.flush()


def _add_profile(db, user_id, profile_id):
    db.add(ChildProfile(
        id=profile_id,
        user_id=user_id,
        nickname=None,
        age_band="3-4",
        created_at=NOW,
        updated_at=NOW,
    ))
    db.flush()


def _add_authored_story(db, user_id, story_id):
    db.add(Story(
        id=story_id,
        title=story_id,
        slug=story_id,
        description=None,
        age_min=3,
        age_max=8,
        duration_seconds=60,
        themes=[],
        owner_user_id=user_id,
    ))
    db.flush()


def _counts(db, user_id):
    db.expire_all()
    return {
        "profiles": db.scalar(
            select(func.count(ChildProfile.id)).where(ChildProfile.user_id == user_id)
        ),
        "stories": db.scalar(
            select(func.count(Story.id)).where(Story.owner_user_id == user_id)
        ),
        "settings": db.scalar(
            select(func.count(PrivacySettings.user_id)).where(
                PrivacySettings.user_id == user_id
            )
        ),
    }


def test_strictly_older_than_90_days_is_selected(db, session_factory):
    user_id = "retention-old"
    _add_user(db, user_id, CUTOFF - timedelta(days=1))
    _add_profile(db, user_id, "retention-old-profile")

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _counts(db, user_id) == {"profiles": 0, "stories": 0, "settings": 0}


def test_exact_boundary_is_skipped(db, session_factory):
    user_id = "retention-boundary"
    _add_user(db, user_id, CUTOFF)
    _add_profile(db, user_id, "retention-boundary-profile")

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _counts(db, user_id) == {"profiles": 1, "stories": 0, "settings": 1}


def test_profile_and_authored_story_are_owner_signals(db, session_factory):
    profile_owner = "retention-profile-owner"
    story_owner = "retention-story-owner"
    clean_inactive = "retention-clean-inactive"
    _add_user(db, profile_owner, CUTOFF - timedelta(days=2))
    _add_profile(db, profile_owner, "retention-profile-owner-profile")
    _add_user(db, story_owner, CUTOFF - timedelta(days=2))
    _add_authored_story(db, story_owner, "retention-story-owner-story")
    _add_user(db, clean_inactive, CUTOFF - timedelta(days=2))

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _counts(db, profile_owner) == {"profiles": 0, "stories": 0, "settings": 0}
    assert _counts(db, story_owner) == {"profiles": 0, "stories": 0, "settings": 0}
    assert _counts(db, clean_inactive) == {"profiles": 0, "stories": 0, "settings": 1}


def test_dry_run_performs_no_deletion(db, session_factory, capsys):
    user_id = "retention-dry-run"
    _add_user(db, user_id, CUTOFF - timedelta(days=1))
    _add_profile(db, user_id, "retention-dry-run-profile")

    exit_code = privacy_retention.run_retention(
        dry_run=True, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _counts(db, user_id) == {"profiles": 1, "stories": 0, "settings": 1}
    assert capsys.readouterr().out.strip() == (
        "attempted=1 deleted=1 skipped=0 failed=0 dry_run=true"
    )


def test_lock_time_activity_recheck_skips(db, session_factory, monkeypatch):
    user_id = "retention-recheck"
    _add_user(db, user_id, CUTOFF - timedelta(days=1))
    _add_profile(db, user_id, "retention-recheck-profile")

    real_lock = privacy_service.lock_user

    def lock_after_becoming_active(lock_db, lock_user_id):
        settings = lock_db.get(PrivacySettings, lock_user_id)
        settings.last_active_at = NOW
        settings.updated_at = NOW
        lock_db.flush()
        return real_lock(lock_db, lock_user_id)

    monkeypatch.setattr(privacy_retention, "lock_user", lock_after_becoming_active)

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _counts(db, user_id) == {"profiles": 1, "stories": 0, "settings": 1}


def test_idempotent_retry_deletes_nothing_more(db, session_factory, capsys):
    user_id = "retention-idempotent"
    _add_user(db, user_id, CUTOFF - timedelta(days=1))
    _add_authored_story(db, user_id, "retention-idempotent-story")

    first = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )
    second = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert first == 0
    assert second == 0
    assert capsys.readouterr().out.splitlines()[1] == (
        "attempted=0 deleted=0 skipped=0 failed=0 dry_run=false"
    )
    assert _counts(db, user_id) == {"profiles": 0, "stories": 0, "settings": 0}


def test_failure_for_one_user_does_not_stop_others(db, session_factory, monkeypatch, capsys):
    failing_user = "retention-failing"
    healthy_user = "retention-healthy"
    _add_user(db, failing_user, CUTOFF - timedelta(days=1))
    _add_profile(db, failing_user, "retention-failing-profile")
    _add_user(db, healthy_user, CUTOFF - timedelta(days=1))
    _add_profile(db, healthy_user, "retention-healthy-profile")

    real_delete = child_data_deletion.delete_child_data

    def delete_unless_failing(delete_db, delete_user_id):
        if delete_user_id == failing_user:
            raise RuntimeError("boom")
        return real_delete(delete_db, delete_user_id)

    monkeypatch.setattr(privacy_retention, "delete_child_data", delete_unless_failing)

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 1
    assert _counts(db, failing_user) == {"profiles": 1, "stories": 0, "settings": 1}
    assert _counts(db, healthy_user) == {"profiles": 0, "stories": 0, "settings": 0}
    assert capsys.readouterr().out.strip() == (
        "attempted=2 deleted=1 skipped=0 failed=1 dry_run=false"
    )


def test_uses_shared_deletion_service(db, session_factory, monkeypatch):
    profile_owner = "retention-shared-profile"
    story_owner = "retention-shared-story"
    _add_user(db, profile_owner, CUTOFF - timedelta(days=1))
    _add_profile(db, profile_owner, "retention-shared-profile-id")
    _add_user(db, story_owner, CUTOFF - timedelta(days=1))
    _add_authored_story(db, story_owner, "retention-shared-story-id")

    calls = []
    real_delete = child_data_deletion.delete_child_data

    def counting_delete(delete_db, delete_user_id):
        calls.append(delete_user_id)
        return real_delete(delete_db, delete_user_id)

    monkeypatch.setattr(privacy_retention, "delete_child_data", counting_delete)

    exit_code = privacy_retention.run_retention(
        dry_run=False, session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert sorted(calls) == sorted([profile_owner, story_owner])
    assert _counts(db, profile_owner) == {"profiles": 0, "stories": 0, "settings": 0}
    assert _counts(db, story_owner) == {"profiles": 0, "stories": 0, "settings": 0}
