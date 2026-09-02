import threading
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import delete, select

from app.models import ChildProfile, ConsentEvent, InteractionEvent, PrivacySettings, Story, StorySession
from app.repositories import privacy as privacy_repo
from app.repositories import sessions as sessions_repo
from app.services import privacy as privacy_service

WAIT_TIMEOUT = 10.0
BLOCK_PROBE = 0.3


def _setup_enabled_user(db, user_id):
    now = datetime.now(timezone.utc)
    profile_id = str(uuid.uuid4())
    story_id = str(uuid.uuid4())
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
        owner_user_id=user_id,
    ))
    db.add(PrivacySettings(
        user_id=user_id,
        accepted_policy_version=privacy_service.CURRENT_PRIVACY_POLICY_VERSION,
        core_storage_accepted_at=now,
        progress_tracking_enabled=True,
        cloud_tts_enabled=False,
        last_active_at=now,
        updated_at=now,
    ))
    db.commit()
    return profile_id, story_id


def _cleanup(db, user_id, profile_id):
    db.rollback()
    db.execute(delete(InteractionEvent).where(
        InteractionEvent.story_session_id.in_(
            select(StorySession.id).where(StorySession.child_profile_id == profile_id)
        )
    ))
    db.execute(delete(StorySession).where(StorySession.child_profile_id == profile_id))
    db.execute(delete(ConsentEvent).where(ConsentEvent.user_id == user_id))
    db.execute(delete(PrivacySettings).where(PrivacySettings.user_id == user_id))
    db.execute(delete(ChildProfile).where(ChildProfile.user_id == user_id))
    db.execute(delete(Story).where(Story.owner_user_id == user_id))
    db.commit()


def test_no_session_write_commits_after_revocation_returns(independent_session_factory):
    user_id = "revoke-race-user"
    writer = independent_session_factory(user_id=user_id)
    revoker = independent_session_factory()
    profile_id, story_id = _setup_enabled_user(writer, user_id)

    lock_held = threading.Event()
    write_released = threading.Event()
    writer_done = threading.Event()
    revocation_done = threading.Event()
    failures = []

    def writer_body():
        try:
            privacy_service.lock_user(writer, user_id)
            settings = privacy_repo.get_settings(writer, user_id)
            privacy_service.require_progress(settings)
            pending = sessions_repo.start(writer, story_id, profile_id, "bedtime")
        except Exception as exc:
            failures.append(exc)
            lock_held.set()
            writer_done.set()
            return
        lock_held.set()
        if not write_released.wait(WAIT_TIMEOUT):
            failures.append(RuntimeError("writer was never released"))
            writer.rollback()
            writer_done.set()
            return
        try:
            writer.commit()
        except Exception as exc:
            failures.append(exc)
        finally:
            writer_done.set()

    def revoker_body():
        try:
            privacy_service.update_settings(
                revoker,
                user_id,
                policy_version=privacy_service.CURRENT_PRIVACY_POLICY_VERSION,
                core_storage_accepted=True,
                progress_tracking_enabled=False,
                cloud_tts_enabled=False,
            )
            revoker.commit()
        except Exception as exc:
            failures.append(exc)
        finally:
            revocation_done.set()

    try:
        writer_thread = threading.Thread(target=writer_body, name="writer")
        writer_thread.start()
        assert lock_held.wait(WAIT_TIMEOUT), "writer never acquired the user lock"
        assert not failures, failures

        revoker_thread = threading.Thread(target=revoker_body, name="revoker")
        revoker_thread.start()
        assert not revocation_done.wait(BLOCK_PROBE), (
            "revocation returned while the writer still held the user lock"
        )

        write_released.set()
        assert writer_done.wait(WAIT_TIMEOUT), "writer never committed"
        assert revocation_done.wait(WAIT_TIMEOUT), "revocation never completed"
        assert not failures, failures

        verifier = independent_session_factory()
        sessions = list(verifier.scalars(
            select(StorySession).where(StorySession.child_profile_id == profile_id)
        ))
        assert len(sessions) == 1
        assert list(verifier.scalars(
            select(InteractionEvent.event_type).where(
                InteractionEvent.story_session_id == sessions[0].id
            )
        )) == ["story_started"]
        assert verifier.get(PrivacySettings, user_id).progress_tracking_enabled is False

        with pytest.raises(privacy_service.PrivacyError) as excinfo:
            privacy_service.lock_user(verifier, user_id)
            settings = privacy_repo.get_settings(verifier, user_id)
            privacy_service.require_progress(settings)
        assert excinfo.value.status_code == 403
        assert excinfo.value.code == "progress_tracking_disabled"

        verifier.rollback()
        assert len(list(verifier.scalars(
            select(StorySession).where(StorySession.child_profile_id == profile_id)
        ))) == 1
    finally:
        write_released.set()
        writer_done.wait(WAIT_TIMEOUT)
        revocation_done.wait(WAIT_TIMEOUT)
        _cleanup(revoker, user_id, profile_id)
