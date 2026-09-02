import uuid

import pytest
from sqlalchemy import select

from app.models import InteractionEvent, StorySession
from app.repositories import sessions as sessions_repo


def _auth(client, device="s-dev"):
    return {"Authorization": f"Bearer {client.post('/v1/auth/device', json={'device_id': device}).json()['token']}"}


def _make_profile(client, h):
    pid = str(uuid.uuid4())
    client.post("/v1/child-profiles",
                json={"id": pid, "age_band": "3-4", "language_code": "en"}, headers=h)
    return pid


def test_start_session_emits_story_started(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_bunny_forest", "mode": "bedtime"},
                       headers=h)
    assert resp.status_code == 200
    sid = resp.json()["id"]
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_started" for e in events)


def test_patch_complete_emits_story_completed(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    patched = client.patch(f"/v1/story-sessions/{sid}",
                          json={"last_page_number": 5, "completed": True}, headers=h).json()
    assert patched["last_page_number"] == 5
    assert patched["completed_at"] is not None
    events = client.get(f"/v1/story-sessions/{sid}/events", headers=h).json()
    assert any(e["event_type"] == "story_completed" for e in events)


def test_record_question_answered_event(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
                      headers=h).json()["id"]
    resp = client.post(f"/v1/story-sessions/{sid}/events",
                      json={"event_type": "question_answered", "page_id": "page_bunny_03",
                            "payload": {"question_id": "q_bunny_02", "answer_id": "a_owl", "is_correct": True}},
                      headers=h)
    assert resp.status_code == 200


def test_list_sessions_by_child(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    client.post("/v1/story-sessions",
                json={"child_profile_id": pid, "story_id": "story_bunny_forest"}, headers=h)
    listed = client.get(f"/v1/story-sessions?child_profile_id={pid}", headers=h).json()
    assert len(listed) == 1


def test_start_session_unknown_story_returns_404(client, seeded):
    h = _auth(client)
    pid = _make_profile(client, h)
    resp = client.post("/v1/story-sessions",
                       json={"child_profile_id": pid, "story_id": "story_does_not_exist"},
                       headers=h)
    assert resp.status_code == 404


def test_session_not_accessible_cross_device(client, seeded):
    h_a = _auth(client, "dev-A")
    h_b = _auth(client, "dev-B")
    pid_a = _make_profile(client, h_a)
    sid = client.post("/v1/story-sessions",
                      json={"child_profile_id": pid_a, "story_id": "story_bunny_forest"},
                      headers=h_a).json()["id"]
    assert client.patch(f"/v1/story-sessions/{sid}", json={"last_page_number": 2}, headers=h_b).status_code == 404
    assert client.get(f"/v1/story-sessions/{sid}/events", headers=h_b).status_code == 404
    assert client.post(f"/v1/story-sessions/{sid}/events",
                       json={"event_type": "page_turned"}, headers=h_b).status_code == 404


def test_session_repositories_flush_without_committing(client, db, seeded, monkeypatch):
    h = _auth(client)
    pid = _make_profile(client, h)

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
    pid = _make_profile(client, h)
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
    pid = _make_profile(client, h)
    session_id = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": pid, "story_id": "story_bunny_forest"},
        headers=h,
    ).json()["id"]
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
