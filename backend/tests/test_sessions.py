import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from app.auth import decode_token
from app.models import InteractionEvent, PrivacySettings, StorySession
from app.repositories import sessions as sessions_repo

POLICY_VERSION = "2026-10-06"


def _auth(client, device="s-dev"):
    return {"Authorization": f"Bearer {client.post('/v1/auth/device', json={'device_id': device}).json()['token']}"}


def _uid(headers):
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _grant_consent(db, user_id, *, progress=False, policy_version=POLICY_VERSION):
    now = datetime.now(timezone.utc)
    settings = db.get(PrivacySettings, user_id)
    if settings is None:
        settings = PrivacySettings(user_id=user_id)
        db.add(settings)
    settings.accepted_policy_version = policy_version
    settings.core_storage_accepted_at = now
    settings.progress_tracking_enabled = progress
    settings.cloud_tts_enabled = False
    settings.last_active_at = now
    settings.updated_at = now
    db.flush()


def _drop_consent(db, user_id):
    settings = db.get(PrivacySettings, user_id)
    if settings is not None:
        db.delete(settings)
        db.flush()


def _make_profile(client, h, db, *, progress=True):
    _grant_consent(db, _uid(h), progress=progress)
    pid = str(uuid.uuid4())
    resp = client.post("/v1/child-profiles",
                       json={"id": pid, "age_band": "3-4", "language_code": "en"}, headers=h)
    assert resp.status_code == 200
    return pid


def _session_count(db, pid):
    return len(list(db.scalars(
        select(StorySession.id).where(StorySession.child_profile_id == pid)
    )))


def _event_types(db, sid):
    return list(db.scalars(
        select(InteractionEvent.event_type).where(
            InteractionEvent.story_session_id == sid
        )
    ))


def _start_session(client, h, pid):
    return client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                       headers=h)


def _setup_disabled_state(client, db, h, state):
    uid = _uid(h)
    if state == "revoked":
        pid = _make_profile(client, h, db)
        sid = _start_session(client, h, pid).json()["id"]
        _grant_consent(db, uid, progress=False)
        db.commit()
        return pid, sid
    pid = _make_profile(client, h, db, progress=False)
    if state == "stale-policy":
        _grant_consent(db, uid, progress=True, policy_version="2026-01-01")
    sid = sessions_repo.start(db, "story_bunny_forest", pid, "bedtime").id
    db.commit()
    return pid, sid


def test_start_session_emits_story_started(client, db, seeded):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    resp = _start_session(client, h, pid)
    assert resp.status_code == 200
    sid = resp.json()["id"]
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_started" for e in events)


def test_patch_complete_emits_story_completed(client, db, seeded):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    sid = _start_session(client, h, pid).json()["id"]
    patched = client.patch(f"/v1/story-sessions/{sid}",
                          json={"last_page_number": 5, "completed": True}, headers=h).json()
    assert patched["last_page_number"] == 5
    assert patched["completed_at"] is not None
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_completed" for e in events)


def test_record_question_answered_event(client, db, seeded):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    sid = _start_session(client, h, pid).json()["id"]
    resp = client.post(f"/v1/story-sessions/{sid}/events",
                       json={"event_type": "question_answered", "page_id": "page_bunny_03",
                             "payload": {"question_id": "q_bunny_02", "answer_id": "a_owl", "is_correct": True}},
                       headers=h)
    assert resp.status_code == 200


def test_list_sessions_by_child(client, db, seeded):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    _start_session(client, h, pid)
    listed = client.get(f"/v1/story-sessions?child_profile_id={pid}", headers=h).json()
    assert len(listed) == 1


def test_start_session_unknown_story_returns_404(client, db, seeded):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_does_not_exist"},
                       headers=h)
    assert resp.status_code == 404


def test_session_not_accessible_cross_device(client, db, seeded):
    h_a = _auth(client, "dev-A")
    h_b = _auth(client, "dev-B")
    pid_a = _make_profile(client, h_a, db)
    sid = _start_session(client, h_a, pid_a).json()["id"]
    assert client.patch(f"/v1/story-sessions/{sid}", json={"last_page_number": 2}, headers=h_b).status_code == 404
    assert client.get(f"/v1/story-sessions/{sid}/events", headers=h_b).status_code == 404
    assert client.post(f"/v1/story-sessions/{sid}/events",
                       json={"event_type": "page_turned"}, headers=h_b).status_code == 404


def test_session_repositories_flush_without_committing(client, db, seeded, monkeypatch):
    h = _auth(client)
    pid = _make_profile(client, h, db)

    def fail_commit():
        raise AssertionError("repository must not commit")

    monkeypatch.setattr(db, "commit", fail_commit)
    session = sessions_repo.start(db, "story_bunny_forest", pid, "standard")
    sessions_repo.patch(db, session, 3, True)
    sessions_repo.record_event(db, session.id, "page_turned")
    session_id = session.id
    db.expunge_all()

    persisted = db.scalar(select(StorySession).where(StorySession.id == session_id))
    assert persisted is not None
    assert persisted.last_page_number == 3
    assert persisted.completed_at is not None
    event_types = set(db.scalars(
        select(InteractionEvent.event_type).where(
            InteractionEvent.story_session_id == session_id
        )
    ))
    assert event_types == {"story_started", "story_completed", "page_turned"}


def test_start_session_and_started_event_are_one_transaction(
    client, db, seeded, monkeypatch
):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    original_record_event = sessions_repo.record_event
    event_ids = []

    def fail_after_event_flush(*args, **kwargs):
        event = original_record_event(*args, **kwargs)
        event_ids.append(event.id)
        raise RuntimeError("fail after event flush")

    monkeypatch.setattr(sessions_repo, "record_event", fail_after_event_flush)
    with pytest.raises(RuntimeError, match="fail after event flush"):
        client.post(
            "/v1/story-sessions",
            json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
            headers=h,
        )

    db.expire_all()
    sessions = list(db.scalars(
        select(StorySession).where(StorySession.child_profile_id == pid)
    ))
    assert sessions == []
    assert db.get(InteractionEvent, event_ids[0]) is None


def test_complete_session_and_completed_event_are_one_transaction(
    client, db, seeded, monkeypatch
):
    h = _auth(client)
    pid = _make_profile(client, h, db)
    session_id = _start_session(client, h, pid).json()["id"]
    original_record_event = sessions_repo.record_event
    event_ids = []

    def fail_after_event_flush(*args, **kwargs):
        event = original_record_event(*args, **kwargs)
        event_ids.append(event.id)
        raise RuntimeError("fail after event flush")

    monkeypatch.setattr(sessions_repo, "record_event", fail_after_event_flush)
    with pytest.raises(RuntimeError, match="fail after event flush"):
        client.patch(
            f"/v1/story-sessions/{session_id}",
            json={"last_page_number": 5, "completed": True},
            headers=h,
        )

    db.expire_all()
    persisted = db.get(StorySession, session_id)
    assert persisted.last_page_number == 0
    assert persisted.completed_at is None
    assert db.get(InteractionEvent, event_ids[0]) is None
    event_types = list(db.scalars(
        select(InteractionEvent.event_type).where(
            InteractionEvent.story_session_id == session_id
        )
    ))
    assert event_types == ["story_started"]


@pytest.mark.parametrize("drop_row", [False, True])
def test_start_session_default_off_returns_403_and_writes_nothing(
    client, db, seeded, drop_row
):
    h = _auth(client)
    uid = _uid(h)
    pid = _make_profile(client, h, db, progress=False)
    if drop_row:
        _drop_consent(db, uid)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid,
                             "story_id": "story_bunny_forest", "mode": "bedtime"},
                       headers=h)
    assert resp.status_code == 403
    assert resp.json() == {"detail": "progress_tracking_disabled"}
    assert _session_count(db, pid) == 0


@pytest.mark.parametrize("state", ["default-off", "revoked", "stale-policy"])
def test_disabled_states_block_session_writes(client, db, seeded, state):
    h = _auth(client)
    pid, sid = _setup_disabled_state(client, db, h, state)
    baseline_events = len(_event_types(db, sid))

    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid,
                             "story_id": "story_bunny_forest", "mode": "bedtime"},
                       headers=h)
    assert resp.status_code == 403
    assert resp.json() == {"detail": "progress_tracking_disabled"}

    resp = client.patch(f"/v1/story-sessions/{sid}",
                        json={"last_page_number": 5, "completed": True}, headers=h)
    assert resp.status_code == 403
    assert resp.json() == {"detail": "progress_tracking_disabled"}

    resp = client.post(f"/v1/story-sessions/{sid}/events",
                       json={"event_type": "page_turned"}, headers=h)
    assert resp.status_code == 403
    assert resp.json() == {"detail": "progress_tracking_disabled"}

    listed = client.get(f"/v1/story-sessions?child_profile_id={pid}", headers=h)
    assert listed.status_code == 200
    assert [s["id"] for s in listed.json()] == [sid]
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h)
    assert events.status_code == 200
    assert len(events.json()) == baseline_events

    db.expire_all()
    assert _session_count(db, pid) == 1
    assert _event_types(db, sid) == ["story_started"]
    persisted = db.get(StorySession, sid)
    assert persisted.last_page_number == 0
    assert persisted.completed_at is None
