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
