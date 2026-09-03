import uuid
from datetime import datetime, timezone

from sqlalchemy import select

from app.auth import decode_token
from app.models import ChildProfile, PrivacySettings
from app.repositories import profiles as profiles_repo

POLICY_VERSION = "2026-08-28"


def _auth(client, device="p-dev"):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _uid(headers):
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _grant_consent(db, user_id):
    now = datetime.now(timezone.utc)
    settings = db.get(PrivacySettings, user_id)
    if settings is None:
        settings = PrivacySettings(user_id=user_id)
        db.add(settings)
    settings.accepted_policy_version = POLICY_VERSION
    settings.core_storage_accepted_at = now
    settings.progress_tracking_enabled = False
    settings.cloud_tts_enabled = False
    settings.last_active_at = now
    settings.updated_at = now
    db.flush()


def _stale_consent(db, user_id):
    settings = db.get(PrivacySettings, user_id)
    assert settings is not None
    settings.accepted_policy_version = "2026-01-01"
    settings.core_storage_accepted_at = datetime.now(timezone.utc)
    db.flush()


def _drop_consent(db, user_id):
    settings = db.get(PrivacySettings, user_id)
    if settings is not None:
        db.delete(settings)
        db.flush()


def _profile_body():
    return {"id": str(uuid.uuid4()), "nickname": "Bun", "age_band": "3-4",
            "language_code": "en", "bedtime_mode_default": False,
            "microphone_enabled": False, "ar_enabled": True}


def test_create_and_list_profile(client, db):
    h = _auth(client)
    _grant_consent(db, _uid(h))
    body = _profile_body()
    created = client.post("/v1/child-profiles", json=body, headers=h)
    assert created.status_code == 200
    assert created.json()["user_id"]  # set from JWT, not body

    listed = client.get("/v1/child-profiles", headers=h).json()
    assert [p["id"] for p in listed] == [body["id"]]


def test_patch_updates_permissions(client, db):
    h = _auth(client)
    _grant_consent(db, _uid(h))
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    patched = client.patch(f"/v1/child-profiles/{body['id']}",
                           json={"microphone_enabled": True}, headers=h)
    assert patched.json()["microphone_enabled"] is True


def test_profiles_isolated_per_device(client, db):
    body = _profile_body()
    h_a = _auth(client, "dev-A")
    _grant_consent(db, _uid(h_a))
    client.post("/v1/child-profiles", json=body, headers=h_a)
    other = client.get("/v1/child-profiles", headers=_auth(client, "dev-B")).json()
    assert other == []


def test_patch_invalid_bool_returns_422(client, db):
    h = _auth(client)
    _grant_consent(db, _uid(h))
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    resp = client.patch(f"/v1/child-profiles/{body['id']}",
                        json={"ar_enabled": "banana"}, headers=h)
    assert resp.status_code == 422


def test_profile_upsert_flushes_without_committing(client, db, monkeypatch):
    headers = _auth(client)
    user_id = decode_token(headers["Authorization"].removeprefix("Bearer "))
    body = _profile_body()

    def fail_commit():
        raise AssertionError("repository must not commit")

    monkeypatch.setattr(db, "commit", fail_commit)
    profiles_repo.upsert(db, user_id, body)
    db.expunge_all()

    profile = db.scalar(select(ChildProfile).where(ChildProfile.id == body["id"]))
    assert profile is not None


def test_create_profile_missing_privacy_row_returns_428_and_writes_nothing(client, db):
    h = _auth(client)
    _drop_consent(db, _uid(h))
    body = _profile_body()
    resp = client.post("/v1/child-profiles", json=body, headers=h)
    assert resp.status_code == 428
    assert resp.json() == {"detail": "privacy_policy_review_required"}
    assert db.get(ChildProfile, body["id"]) is None


def test_create_profile_stale_consent_returns_428_and_writes_nothing(client, db):
    h = _auth(client)
    _stale_consent(db, _uid(h))
    body = _profile_body()
    resp = client.post("/v1/child-profiles", json=body, headers=h)
    assert resp.status_code == 428
    assert resp.json() == {"detail": "privacy_policy_review_required"}
    assert db.get(ChildProfile, body["id"]) is None


def test_create_profile_current_consent_succeeds(client, db):
    h = _auth(client)
    _grant_consent(db, _uid(h))
    body = _profile_body()
    resp = client.post("/v1/child-profiles", json=body, headers=h)
    assert resp.status_code == 200
    assert resp.json()["id"] == body["id"]


def test_patch_profile_missing_privacy_row_returns_428_and_writes_nothing(client, db):
    h = _auth(client)
    uid = _uid(h)
    _grant_consent(db, uid)
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    _drop_consent(db, uid)
    resp = client.patch(f"/v1/child-profiles/{body['id']}",
                        json={"nickname": "Changed"}, headers=h)
    assert resp.status_code == 428
    assert resp.json() == {"detail": "privacy_policy_review_required"}
    listed = client.get("/v1/child-profiles", headers=h).json()
    assert [p["nickname"] for p in listed] == ["Bun"]


def test_patch_profile_stale_consent_returns_428_and_writes_nothing(client, db):
    h = _auth(client)
    uid = _uid(h)
    _grant_consent(db, uid)
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    _stale_consent(db, uid)
    resp = client.patch(f"/v1/child-profiles/{body['id']}",
                        json={"nickname": "Changed"}, headers=h)
    assert resp.status_code == 428
    assert resp.json() == {"detail": "privacy_policy_review_required"}
    listed = client.get("/v1/child-profiles", headers=h).json()
    assert [p["nickname"] for p in listed] == ["Bun"]


def test_patch_profile_current_consent_succeeds(client, db):
    h = _auth(client)
    _grant_consent(db, _uid(h))
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    resp = client.patch(f"/v1/child-profiles/{body['id']}",
                        json={"microphone_enabled": True}, headers=h)
    assert resp.status_code == 200
    assert resp.json()["microphone_enabled"] is True


def test_profile_list_available_without_consent(client, db):
    h = _auth(client)
    uid = _uid(h)
    _grant_consent(db, uid)
    body = _profile_body()
    client.post("/v1/child-profiles", json=body, headers=h)
    _drop_consent(db, uid)
    resp = client.get("/v1/child-profiles", headers=h)
    assert resp.status_code == 200
    assert [p["id"] for p in resp.json()] == [body["id"]]
