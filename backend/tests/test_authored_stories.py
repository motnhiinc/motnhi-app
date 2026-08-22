import uuid as _uuid

from app.auth import decode_token
from app.models import Story


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
