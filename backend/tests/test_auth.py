import pytest
from sqlalchemy import select

from app.auth import create_token, decode_token
from app.models import Device, PrivacySettings, User
from app.repositories import privacy as privacy_repo
from app.routers import auth as auth_router


def test_token_roundtrip():
    token = create_token("user-123")
    assert decode_token(token) == "user-123"


def test_decode_rejects_garbage():
    with pytest.raises(Exception):
        decode_token("not-a-jwt")


def test_device_auth_registers_then_requires_secret(client):
    first = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert first.status_code == 200
    body = first.json()
    assert body["token"] and body["user_id"] and body["device_secret"]

    again = client.post("/v1/auth/device",
                        json={"device_id": "device-abc", "device_secret": body["device_secret"]})
    assert again.status_code == 200
    assert again.json()["user_id"] == body["user_id"]
    assert again.json()["device_secret"] is None

    assert client.post("/v1/auth/device", json={"device_id": "device-abc"}).status_code == 401
    assert client.post("/v1/auth/device",
                       json={"device_id": "device-abc", "device_secret": "wrong"}).status_code == 401


def test_device_registration_creates_default_privacy_state(client, db):
    response = client.post("/v1/auth/device", json={"device_id": "device-privacy"})
    assert response.status_code == 200

    user = db.scalar(select(User))
    device = db.scalar(select(Device))
    settings = db.scalar(select(PrivacySettings))

    assert user is not None
    assert device is not None
    assert settings is not None
    assert device.user_id == user.id
    assert settings.user_id == user.id
    assert settings.accepted_policy_version is None
    assert settings.core_storage_accepted_at is None
    assert settings.progress_tracking_enabled is False
    assert settings.cloud_tts_enabled is False
    assert settings.last_active_at is not None
    assert settings.updated_at is not None
    assert settings.last_active_at.tzinfo is not None
    assert settings.updated_at.tzinfo is not None


def test_device_registration_rollback_creates_no_privacy_state(client, db, monkeypatch):
    original = privacy_repo.create_default_settings

    def failing_create_default_settings(session, user_id, now):
        original(session, user_id, now)
        raise RuntimeError("simulated registration failure")

    monkeypatch.setattr(
        auth_router.privacy_repo,
        "create_default_settings",
        failing_create_default_settings,
    )

    with pytest.raises(RuntimeError):
        client.post("/v1/auth/device", json={"device_id": "device-rollback"})

    db.rollback()
    assert db.scalar(select(User)) is None
    assert db.scalar(select(Device)) is None
    assert db.scalar(select(PrivacySettings)) is None
