import threading
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError

from app.models import ChildProfile, ConsentEvent, InteractionEvent, PrivacySettings, Story, StorySession
from app.repositories import privacy as privacy_repo
from app.repositories import sessions as sessions_repo
from app.services import child_data_deletion
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
                page_image_validation_enabled=False,
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


def _add_profile(db, user_id, profile_id):
    now = datetime.now(timezone.utc)
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
    db.flush()


def _add_authored_story(db, user_id, story_id):
    now = datetime.now(timezone.utc)
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
    db.flush()


@pytest.mark.parametrize("write_kind", ["profile", "story", "session", "event"])
def test_no_child_data_write_commits_after_deletion_returns(
    independent_session_factory, write_kind
):
    user_id = f"child-delete-race-{write_kind}"
    setup = independent_session_factory(user_id=user_id)
    writer = independent_session_factory()
    deleter = independent_session_factory()
    profile_id, story_id = _setup_enabled_user(setup, user_id)

    preexisting_session_id = None
    if write_kind in ("session", "event"):
        preexisting = sessions_repo.start(setup, story_id, profile_id, "library")
        setup.commit()
        preexisting_session_id = preexisting.id

    write_id = str(uuid.uuid4())
    lock_held = threading.Event()
    write_released = threading.Event()
    writer_done = threading.Event()
    deletion_done = threading.Event()
    failures = []

    def writer_body():
        try:
            privacy_service.lock_user(writer, user_id)
            if write_kind == "profile":
                _add_profile(writer, user_id, write_id)
            elif write_kind == "story":
                _add_authored_story(writer, user_id, write_id)
            elif write_kind == "session":
                sessions_repo.start(writer, story_id, profile_id, "bedtime")
            else:
                sessions_repo.record_event(
                    writer, preexisting_session_id, "page_turn"
                )
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

    def deleter_body():
        try:
            privacy_service.lock_user(deleter, user_id)
            child_data_deletion.delete_child_data(deleter, user_id)
            deleter.commit()
        except Exception as exc:
            failures.append(exc)
            deleter.rollback()
        finally:
            deletion_done.set()

    try:
        writer_thread = threading.Thread(target=writer_body, name="writer")
        writer_thread.start()
        assert lock_held.wait(WAIT_TIMEOUT), "writer never acquired the user lock"
        assert not failures, failures

        deleter_thread = threading.Thread(target=deleter_body, name="deleter")
        deleter_thread.start()
        assert not deletion_done.wait(BLOCK_PROBE), (
            "child-data deletion returned while the writer still held the user lock"
        )

        write_released.set()
        assert writer_done.wait(WAIT_TIMEOUT), "writer never committed"
        assert deletion_done.wait(WAIT_TIMEOUT), "deletion never completed"
        assert not failures, failures

        verifier = independent_session_factory()
        assert verifier.scalar(select(func.count(ChildProfile.id)).where(
            ChildProfile.user_id == user_id
        )) == 0
        assert verifier.scalar(select(func.count(Story.id)).where(
            Story.owner_user_id == user_id
        )) == 0
        assert verifier.scalar(select(func.count(StorySession.id)).where(
            StorySession.child_profile_id == profile_id
        )) == 0
        if preexisting_session_id is not None:
            assert verifier.scalar(select(func.count(InteractionEvent.id)).where(
                InteractionEvent.story_session_id == preexisting_session_id
            )) == 0
        if write_kind == "profile":
            assert verifier.get(ChildProfile, write_id) is None
        elif write_kind == "story":
            assert verifier.get(Story, write_id) is None

        with pytest.raises(IntegrityError):
            sessions_repo.start(verifier, story_id, profile_id, "library")
            verifier.flush()
        verifier.rollback()
        assert verifier.scalar(select(func.count(StorySession.id)).where(
            StorySession.child_profile_id == profile_id
        )) == 0
    finally:
        write_released.set()
        writer_done.wait(WAIT_TIMEOUT)
        deletion_done.wait(WAIT_TIMEOUT)
        _cleanup(setup, user_id, profile_id)
