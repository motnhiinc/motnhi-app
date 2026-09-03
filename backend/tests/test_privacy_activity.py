from datetime import datetime, timedelta, timezone

from sqlalchemy import delete
from sqlalchemy.exc import SQLAlchemyError

from app.auth import get_current_user
from app.main import app as fastapi_app
from app.models import PrivacySettings, User
from app.repositories import privacy as privacy_repo
from app.services import privacy as privacy_service

NOW = datetime(2026, 9, 3, 12, 0, 0, tzinfo=timezone.utc)


def _freeze_clock(monkeypatch) -> None:
    monkeypatch.setattr(privacy_service, "utc_now", lambda: NOW)


def _auth(client, device: str) -> tuple[dict[str, str], str]:
    body = client.post("/v1/auth/device", json={"device_id": device}).json()
    return {"Authorization": f"Bearer {body['token']}"}, body["user_id"]


def _set_last_active(db, user_id: str, value: datetime) -> None:
    settings = db.get(PrivacySettings, user_id)
    settings.last_active_at = value
    settings.updated_at = value
    db.flush()


def _add_user(db, user_id: str, at: datetime) -> None:
    db.add(User(
        id=user_id,
        email=None,
        auth_provider="device",
        created_at=at,
        updated_at=at,
    ))
    db.flush()


def test_touch_activity_if_due_updates_when_stale(db):
    user_id = "activity-svc-user"
    created = NOW - timedelta(days=2)
    _add_user(db, user_id, created)
    privacy_repo.create_default_settings(db, user_id, created)

    assert privacy_service.touch_activity_if_due(db, user_id, NOW - timedelta(days=1)) is True
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW - timedelta(days=1)
    assert settings.updated_at == NOW - timedelta(days=1)

    assert privacy_service.touch_activity_if_due(db, user_id, NOW - timedelta(days=1)) is False
    assert privacy_service.touch_activity_if_due(db, user_id, NOW) is True
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW
    assert settings.updated_at == NOW


def test_touch_activity_if_due_throttles_same_utc_date(db):
    user_id = "activity-svc-same-date"
    created = NOW - timedelta(days=2)
    _add_user(db, user_id, created)
    privacy_repo.create_default_settings(db, user_id, created)
    same_day = NOW - timedelta(hours=1)
    _set_last_active(db, user_id, same_day)

    assert privacy_service.touch_activity_if_due(db, user_id, NOW) is False
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == same_day
    assert settings.updated_at == same_day


def test_touch_activity_if_due_missing_row_returns_false(db):
    user_id = "activity-svc-missing"
    _add_user(db, user_id, NOW)

    assert privacy_service.touch_activity_if_due(db, user_id, NOW) is False
    assert db.get(PrivacySettings, user_id) is None


def test_activity_endpoint_returns_204_and_updates_when_due(client, db, monkeypatch):
    headers, user_id = _auth(client, "activity-endpoint-due")
    _freeze_clock(monkeypatch)
    _set_last_active(db, user_id, NOW - timedelta(days=1))

    user = db.get(User, user_id)
    fastapi_app.dependency_overrides[get_current_user] = lambda: user
    try:
        response = client.post("/v1/privacy/activity", headers=headers)
    finally:
        fastapi_app.dependency_overrides.pop(get_current_user, None)

    assert response.status_code == 204
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW
    assert settings.updated_at == NOW


def test_activity_endpoint_throttles_same_utc_date(client, db, monkeypatch):
    headers, user_id = _auth(client, "activity-endpoint-throttle")
    _freeze_clock(monkeypatch)
    same_day = NOW - timedelta(hours=1)
    _set_last_active(db, user_id, same_day)

    assert client.post("/v1/privacy/activity", headers=headers).status_code == 204
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == same_day
    assert settings.updated_at == same_day


def test_activity_endpoint_updates_next_utc_date(client, db, monkeypatch):
    headers, user_id = _auth(client, "activity-endpoint-next")
    _freeze_clock(monkeypatch)
    _set_last_active(db, user_id, NOW - timedelta(days=1))

    assert client.post("/v1/privacy/activity", headers=headers).status_code == 204
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW


def test_auth_touch_updates_legacy_request_at_most_once_per_utc_date(client, db, monkeypatch):
    headers, user_id = _auth(client, "activity-auth-touch")
    _freeze_clock(monkeypatch)
    _set_last_active(db, user_id, NOW - timedelta(days=1))

    assert client.get("/v1/privacy", headers=headers).status_code == 200
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW

    assert client.get("/v1/privacy", headers=headers).status_code == 200
    settings = db.get(PrivacySettings, user_id)
    assert settings.last_active_at == NOW


def test_auth_touch_does_not_recreate_deleted_row(client, db):
    headers, user_id = _auth(client, "activity-deleted-row")

    db.execute(delete(PrivacySettings).where(PrivacySettings.user_id == user_id))
    db.expire_all()
    assert db.get(PrivacySettings, user_id) is None
    assert db.get(User, user_id) is not None

    assert client.post("/v1/privacy/activity", headers=headers).status_code == 204
    assert db.get(PrivacySettings, user_id) is None

    assert client.get("/v1/privacy", headers=headers).status_code == 200
    assert db.get(PrivacySettings, user_id) is not None


def test_auth_touch_failure_does_not_break_authentication(client, db, monkeypatch):
    headers, _ = _auth(client, "activity-auth-touch-failure")

    def _raise(*args, **kwargs):
        raise SQLAlchemyError("touch failed")

    monkeypatch.setattr(privacy_service, "touch_activity_if_due", _raise)

    assert client.get("/v1/privacy", headers=headers).status_code == 200
