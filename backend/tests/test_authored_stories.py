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
