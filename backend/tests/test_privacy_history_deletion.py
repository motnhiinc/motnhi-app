from datetime import datetime, timezone

from sqlalchemy import func, select

from app.auth import decode_token
from app.models import (
    ChildProfile,
    ConsentEvent,
    InteractionEvent,
    PrivacySettings,
    Story,
    StorySession,
)
from app.repositories import privacy as privacy_repo
from app.services import privacy as privacy_service

NOW = datetime.now(timezone.utc)

PROFILE_1 = "hist-del-profile-1"
PROFILE_2 = "hist-del-profile-2"
CURATED_STORY = "hist-del-curated"
AUTHORED_STORY = "hist-del-authored"
SESSION_1 = "hist-del-session-1"
SESSION_2 = "hist-del-session-2"


def _auth(client, device="p-hist-del"):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _user_id(headers) -> str:
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _put_body():
    return {
        "policy_version": privacy_service.CURRENT_PRIVACY_POLICY_VERSION,
        "core_storage_accepted": True,
        "progress_tracking_enabled": False,
        "cloud_tts_enabled": False,
    }


def _seed(db, user_id):
    for profile_id in (PROFILE_1, PROFILE_2):
        db.add(ChildProfile(
            id=profile_id,
            user_id=user_id,
            nickname=None,
            age_band="3-4",
            language_code="en",
            bedtime_mode_default=False,
            microphone_enabled=False,
            ar_enabled=True,
            created_at=NOW,
            updated_at=NOW,
        ))
    db.add(Story(
        id=CURATED_STORY,
        title="curated",
        slug=CURATED_STORY,
        description=None,
        age_min=3,
        age_max=8,
        language_code="en",
        duration_seconds=60,
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=None,
    ))
    db.add(Story(
        id=AUTHORED_STORY,
        title="authored",
        slug=AUTHORED_STORY,
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
    db.add(StorySession(
        id=SESSION_1,
        child_profile_id=PROFILE_1,
        story_id=CURATED_STORY,
        started_at=NOW,
        completed_at=None,
        last_page_number=1,
        mode="library",
    ))
    db.add(StorySession(
        id=SESSION_2,
        child_profile_id=PROFILE_2,
        story_id=AUTHORED_STORY,
        started_at=NOW,
        completed_at=None,
        last_page_number=1,
        mode="library",
    ))
    db.flush()
    for session_id in (SESSION_1, SESSION_2):
        for page in (1, 2):
            db.add(InteractionEvent(
                id=f"hist-del-event-{session_id}-{page}",
                story_session_id=session_id,
                event_type="page_view",
                page_id=f"page-{page}",
                payload={},
                created_at=NOW,
            ))
    db.flush()


def _session_count(db):
    return db.scalar(
        select(func.count()).select_from(StorySession).where(
            StorySession.id.in_([SESSION_1, SESSION_2])
        )
    )


def _event_count(db):
    return db.scalar(
        select(func.count()).select_from(InteractionEvent).where(
            InteractionEvent.story_session_id.in_([SESSION_1, SESSION_2])
        )
    )


def _consent_count(db, user_id):
    return db.scalar(
        select(func.count()).select_from(ConsentEvent).where(
            ConsentEvent.user_id == user_id
        )
    )


def test_delete_reading_history_requires_auth(client, db):
    resp = client.delete("/v1/privacy/reading-history")
    assert resp.status_code == 401


def test_delete_reading_history_removes_sessions_and_events_only(client, db):
    h = _auth(client)
    user_id = _user_id(h)
    client.put("/v1/privacy", json=_put_body(), headers=h)
    _seed(db, user_id)
    consent_before = _consent_count(db, user_id)
    assert _session_count(db) == 2
    assert _event_count(db) == 4

    resp = client.delete("/v1/privacy/reading-history", headers=h)

    assert resp.status_code == 204
    db.expire_all()

    assert _session_count(db) == 0
    assert _event_count(db) == 0
    assert db.get(ChildProfile, PROFILE_1) is not None
    assert db.get(ChildProfile, PROFILE_2) is not None
    assert db.get(Story, CURATED_STORY) is not None
    assert db.get(Story, AUTHORED_STORY) is not None
    assert db.get(PrivacySettings, user_id) is not None
    assert _consent_count(db, user_id) == consent_before

    body = client.get("/v1/privacy", headers=h).json()
    assert body["counts"] == {
        "child_profiles": 2,
        "authored_stories": 1,
        "story_sessions": 0,
        "interaction_events": 0,
    }


def test_delete_reading_history_is_repeatable(client, db):
    h = _auth(client, "p-hist-del-repeat")
    user_id = _user_id(h)
    client.put("/v1/privacy", json=_put_body(), headers=h)
    _seed(db, user_id)

    first = client.delete("/v1/privacy/reading-history", headers=h)
    assert first.status_code == 204

    second = client.delete("/v1/privacy/reading-history", headers=h)
    assert second.status_code == 204
    db.expire_all()
    assert _session_count(db) == 0
    assert _event_count(db) == 0


def test_delete_reading_history_rollback_keeps_history(client, db, monkeypatch):
    h = _auth(client, "p-hist-del-rollback")
    user_id = _user_id(h)
    client.put("/v1/privacy", json=_put_body(), headers=h)
    _seed(db, user_id)
    db.commit()
    original = privacy_repo.delete_reading_history

    def failing_delete(session, uid):
        original(session, uid)
        raise privacy_service.PrivacyError(500, "forced_failure")

    monkeypatch.setattr(privacy_service, "delete_reading_history", failing_delete)

    resp = client.delete("/v1/privacy/reading-history", headers=h)

    assert resp.status_code == 500
    db.expire_all()

    assert _session_count(db) == 2
    assert _event_count(db) == 4
    assert db.get(ChildProfile, PROFILE_1) is not None
    assert db.get(Story, AUTHORED_STORY) is not None
