import uuid as _uuid

from sqlalchemy import select

from app.auth import decode_token
from app.models import (
    InteractionEvent,
    NarrationSegment,
    Story,
    StoryPage,
    StorySession,
)
from app.repositories import stories as stories_repo
from app.schemas import CreateStoryRequest


def _auth(client, device_id="d1"):
    token = client.post("/v1/auth/device", json={"device_id": device_id}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_story_model_has_nullable_owner(db):
    story = Story(
        id=str(_uuid.uuid4()), title="t", slug="authored-" + str(_uuid.uuid4()),
        age_min=3, age_max=8, language_code="en", duration_seconds=0,
        content_status="published", themes=[],
    )
    db.add(story)
    db.flush()
    assert story.owner_user_id is None


def test_curated_story_reports_is_authored_false(client, seeded):
    resp = client.get("/v1/stories", headers=_auth(client))
    assert resp.status_code == 200
    assert all(s["is_authored"] is False for s in resp.json()["stories"])


def _make_authored(db, owner_user_id, title="Mine"):
    story = Story(
        id=str(_uuid.uuid4()), title=title, slug="authored-" + str(_uuid.uuid4()),
        age_min=3, age_max=8, language_code="en", duration_seconds=60,
        content_status="published", themes=[], owner_user_id=owner_user_id,
    )
    db.add(story)
    db.flush()
    return story


def _user_id_for(client, device_id):
    token = client.post("/v1/auth/device", json={"device_id": device_id}).json()["token"]
    return decode_token(token), {"Authorization": f"Bearer {token}"}


def test_owner_sees_own_authored_story_in_library(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    _make_authored(db, uid, title="Owner Story")
    titles = [s["title"] for s in client.get("/v1/stories", headers=headers).json()["stories"]]
    assert "Owner Story" in titles


def test_other_user_does_not_see_authored_story_in_library(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    _make_authored(db, owner_uid, title="Owner Story")
    _, other_headers = _user_id_for(client, "other-device")
    titles = [s["title"] for s in client.get("/v1/stories", headers=other_headers).json()["stories"]]
    assert "Owner Story" not in titles


def test_authored_story_reports_is_authored_true(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story = _make_authored(db, uid)
    entry = next(
        s for s in client.get("/v1/stories", headers=headers).json()["stories"]
        if s["id"] == story.id
    )
    assert entry["is_authored"] is True


def test_other_user_gets_404_on_authored_detail(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    assert client.get(f"/v1/stories/{story.id}", headers=other_headers).status_code == 404


def test_owner_gets_200_on_own_authored_detail(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story = _make_authored(db, uid)
    assert client.get(f"/v1/stories/{story.id}", headers=headers).status_code == 200


def _profile_for(client, headers):
    return client.post(
        "/v1/child-profiles",
        json={"id": str(_uuid.uuid4()), "age_band": "5-6"},
        headers=headers,
    ).json()


def test_other_user_cannot_start_session_on_authored_story(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    profile = _profile_for(client, other_headers)
    resp = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": profile["id"], "story_id": story.id},
        headers=other_headers,
    )
    assert resp.status_code == 404


def test_owner_can_start_session_on_own_authored_story(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    story = _make_authored(db, uid)
    profile = _profile_for(client, headers)
    resp = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": profile["id"], "story_id": story.id},
        headers=headers,
    )
    assert resp.status_code == 200


def test_other_user_gets_404_on_authored_image_target_manifest(client, db, seeded):
    owner_uid, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, owner_uid)
    _, other_headers = _user_id_for(client, "other-device")
    resp = client.get(
        f"/v1/stories/{story.id}/image-target-manifest", headers=other_headers
    )
    assert resp.status_code == 404


def _payload(pages=None, title="My Book", language="en"):
    pages = pages if pages is not None else [
        {"page_number": 1, "page_text": "Once upon a time there was a fox."},
        {"page_number": 2, "page_text": "The fox found a red balloon."},
    ]
    return {"title": title, "language_code": language, "pages": pages}


def test_create_story_returns_it_and_sets_owner(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    resp = client.post("/v1/stories", json=_payload(), headers=headers)
    assert resp.status_code == 201
    body = resp.json()
    assert body["title"] == "My Book"
    assert body["is_authored"] is True
    assert body["slug"].startswith("authored-")
    assert body["duration_seconds"] >= 60


def test_created_story_round_trips_with_one_segment_per_page(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    detail = client.get(f"/v1/stories/{story_id}", headers=headers).json()
    assert len(detail["pages"]) == 2
    assert len(detail["segments"]) == 2
    assert sorted(p["page_number"] for p in detail["pages"]) == [1, 2]
    for seg in detail["segments"]:
        assert seg["speaker_key"] == "narrator"
        assert seg["audio_asset_id"] is None
        assert seg["sort_order"] == 0
    assert "The fox found a red balloon." in {s["text"] for s in detail["segments"]}


def test_created_story_appears_in_library(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    client.post("/v1/stories", json=_payload(), headers=headers)
    titles = [s["title"] for s in client.get("/v1/stories", headers=headers).json()["stories"]]
    assert "My Book" in titles


def test_create_requires_auth(client, seeded):
    assert client.post("/v1/stories", json=_payload()).status_code == 401


def test_create_rejects_empty_pages(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(pages=[]), headers=headers).status_code == 422


def test_create_rejects_too_many_pages(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": i + 1, "page_text": "x"} for i in range(51)]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_non_contiguous_page_numbers(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "a"}, {"page_number": 3, "page_text": "b"}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_duplicate_page_numbers(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "a"}, {"page_number": 1, "page_text": "b"}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_overlong_page_text(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    pages = [{"page_number": 1, "page_text": "x" * 4001}]
    assert client.post("/v1/stories", json=_payload(pages=pages), headers=headers).status_code == 422


def test_create_rejects_blank_title(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(title="   "), headers=headers).status_code == 422


def test_create_rejects_unsupported_language(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.post("/v1/stories", json=_payload(language="fr"), headers=headers).status_code == 422


def test_create_enforces_story_cap(client, db, seeded):
    uid, headers = _user_id_for(client, "owner-device")
    for _ in range(100):
        _make_authored(db, uid)
    db.flush()
    assert client.post("/v1/stories", json=_payload(), headers=headers).status_code == 409


def test_delete_after_reading_succeeds_and_clears_sessions(client, db, seeded):
    _, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    profile = _profile_for(client, headers)

    # Read it exactly as the player does: this creates a story_session and a
    # story_started interaction_event, which is what breaks a naive delete.
    session = client.post(
        "/v1/story-sessions",
        json={"child_profile_id": profile["id"], "story_id": story_id},
        headers=headers,
    ).json()
    assert db.get(StorySession, session["id"]) is not None

    resp = client.delete(f"/v1/stories/{story_id}", headers=headers)
    assert resp.status_code == 204

    assert db.get(StorySession, session["id"]) is None
    assert list(db.scalars(
        select(InteractionEvent).where(
            InteractionEvent.story_session_id == session["id"]
        )
    )) == []
    assert client.get(f"/v1/stories/{story_id}", headers=headers).status_code == 404


def test_delete_cascades_pages_and_segments(client, db, seeded):
    _, headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=headers).json()["id"]
    assert client.delete(f"/v1/stories/{story_id}", headers=headers).status_code == 204
    assert list(db.scalars(
        select(StoryPage).where(StoryPage.story_id == story_id)
    )) == []
    assert list(db.scalars(
        select(NarrationSegment).where(NarrationSegment.story_id == story_id)
    )) == []


def test_delete_is_owner_only(client, seeded):
    _, owner_headers = _user_id_for(client, "owner-device")
    story_id = client.post("/v1/stories", json=_payload(), headers=owner_headers).json()["id"]
    _, other_headers = _user_id_for(client, "other-device")
    assert client.delete(f"/v1/stories/{story_id}", headers=other_headers).status_code == 404
    assert client.get(f"/v1/stories/{story_id}", headers=owner_headers).status_code == 200


def test_delete_rejects_curated_story(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    curated_id = client.get("/v1/stories", headers=headers).json()["stories"][0]["id"]
    assert client.delete(f"/v1/stories/{curated_id}", headers=headers).status_code == 404
    assert client.get(f"/v1/stories/{curated_id}", headers=headers).status_code == 200


def test_delete_unknown_story_404s(client, seeded):
    _, headers = _user_id_for(client, "owner-device")
    assert client.delete(f"/v1/stories/{_uuid.uuid4()}", headers=headers).status_code == 404


def test_create_authored_flushes_without_committing(client, db, monkeypatch):
    user_id, _ = _user_id_for(client, "owner-device")

    def fail_commit():
        raise AssertionError("repository must not commit")

    monkeypatch.setattr(db, "commit", fail_commit)
    story = stories_repo.create_authored(
        db, user_id, CreateStoryRequest.model_validate(_payload())
    )
    story_id = story.id
    db.expunge_all()

    assert db.scalar(select(Story).where(Story.id == story_id)) is not None


def test_delete_authored_flushes_without_committing(client, db, monkeypatch):
    user_id, _ = _user_id_for(client, "owner-device")
    story = _make_authored(db, user_id)
    story_id = story.id

    def fail_commit():
        raise AssertionError("repository must not commit")

    monkeypatch.setattr(db, "commit", fail_commit)
    assert stories_repo.delete_authored(db, user_id, story_id) is True
    db.expunge_all()

    assert db.scalar(select(Story).where(Story.id == story_id)) is None
