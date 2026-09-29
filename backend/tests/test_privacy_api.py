from datetime import datetime, timezone

from sqlalchemy import delete, select

from app.auth import decode_token
from app.models import ChildProfile, PrivacySettings, Story, User
from app.services import privacy as privacy_service

REVIEW_REQUIRED = {"detail": "privacy_policy_review_required"}


def _auth(client, device="p-privacy-dev"):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _user_id(headers) -> str:
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _put_body(**overrides):
    body = {
        "policy_version": privacy_service.CURRENT_PRIVACY_POLICY_VERSION,
        "core_storage_accepted": True,
        "progress_tracking_enabled": False,
        "cloud_tts_enabled": False,
        "page_image_validation_enabled": False,
    }
    body.update(overrides)
    return body


def test_privacy_requires_auth_get_and_put(client):
    assert client.get("/v1/privacy").status_code == 401
    assert client.put("/v1/privacy", json=_put_body()).status_code == 401


def test_get_default_state_for_fresh_device(client):
    h = _auth(client, "p-privacy-fresh")

    resp = client.get("/v1/privacy", headers=h)

    assert resp.status_code == 200
    body = resp.json()
    assert list(body) == [
        "current_policy_version",
        "accepted_policy_version",
        "review_required",
        "core_storage_accepted_at",
        "progress_tracking_enabled",
        "cloud_tts_enabled",
        "page_image_validation_enabled",
        "effective_progress_tracking_enabled",
        "effective_cloud_tts_enabled",
        "effective_page_image_validation_enabled",
        "last_active_at",
        "updated_at",
        "counts",
    ]
    assert body["current_policy_version"] == "2026-09-26"
    assert body["accepted_policy_version"] is None
    assert body["review_required"] is True
    assert body["core_storage_accepted_at"] is None
    assert body["progress_tracking_enabled"] is False
    assert body["cloud_tts_enabled"] is False
    assert body["page_image_validation_enabled"] is False
    assert body["effective_progress_tracking_enabled"] is False
    assert body["effective_cloud_tts_enabled"] is False
    assert body["effective_page_image_validation_enabled"] is False
    last_active = datetime.fromisoformat(body["last_active_at"].replace("Z", "+00:00"))
    updated = datetime.fromisoformat(body["updated_at"].replace("Z", "+00:00"))
    assert abs((datetime.now(timezone.utc) - last_active).total_seconds()) < 60
    assert abs((datetime.now(timezone.utc) - updated).total_seconds()) < 60
    assert body["counts"] == {
        "child_profiles": 0,
        "authored_stories": 0,
        "story_sessions": 0,
        "interaction_events": 0,
    }


def test_put_full_consent_updates_state(client):
    h = _auth(client, "p-privacy-put")

    resp = client.put("/v1/privacy", json=_put_body(
        progress_tracking_enabled=True,
        cloud_tts_enabled=True,
        page_image_validation_enabled=True,
    ), headers=h)

    assert resp.status_code == 200
    body = resp.json()
    assert body["current_policy_version"] == "2026-09-26"
    assert body["accepted_policy_version"] == "2026-09-26"
    assert body["review_required"] is False
    assert body["core_storage_accepted_at"] is not None
    assert body["progress_tracking_enabled"] is True
    assert body["cloud_tts_enabled"] is True
    assert body["effective_progress_tracking_enabled"] is True
    assert body["effective_cloud_tts_enabled"] is True
    assert body["effective_page_image_validation_enabled"] is True

    follow_up = client.get("/v1/privacy", headers=h).json()
    assert follow_up["accepted_policy_version"] == "2026-09-26"
    assert follow_up["review_required"] is False
    assert follow_up["core_storage_accepted_at"] == body["core_storage_accepted_at"]


def test_put_stale_policy_version_rejected(client):
    h = _auth(client, "p-privacy-stale")

    resp = client.put("/v1/privacy", json=_put_body(
        policy_version="2020-01-01",
    ), headers=h)

    assert resp.status_code == 428
    assert resp.json() == REVIEW_REQUIRED


def test_page_image_consent_is_separate_and_off_by_default(client):
    headers = _auth(client, "p-page-image-consent")
    initial = client.get("/v1/privacy", headers=headers).json()
    assert initial["page_image_validation_enabled"] is False
    assert initial["effective_page_image_validation_enabled"] is False

    narration_only = client.put("/v1/privacy", headers=headers, json=_put_body(
        cloud_tts_enabled=True,
        page_image_validation_enabled=False,
    )).json()
    assert narration_only["effective_cloud_tts_enabled"] is True
    assert narration_only["effective_page_image_validation_enabled"] is False

    both = client.put("/v1/privacy", headers=headers, json=_put_body(
        cloud_tts_enabled=True,
        page_image_validation_enabled=True,
    )).json()
    assert both["effective_cloud_tts_enabled"] is True
    assert both["effective_page_image_validation_enabled"] is True


def test_previous_policy_acceptance_requires_review(client, db):
    headers = _auth(client, "p-page-image-old-policy")
    response = client.get("/v1/privacy", headers=headers).json()
    settings = db.get(PrivacySettings, _user_id(headers))
    settings.accepted_policy_version = "2026-08-28"
    db.flush()

    response = client.get("/v1/privacy", headers=headers).json()
    assert response["current_policy_version"] == "2026-09-26"
    assert response["review_required"] is True
    assert response["effective_page_image_validation_enabled"] is False


def test_put_unchecked_core_storage_rejected(client):
    h = _auth(client, "p-privacy-unchecked")

    resp = client.put("/v1/privacy", json=_put_body(
        core_storage_accepted=False,
    ), headers=h)

    assert resp.status_code == 428
    assert resp.json() == REVIEW_REQUIRED


def test_effective_flags_reflect_current_policy_acceptance(client):
    h = _auth(client, "p-privacy-effective")

    fresh = client.get("/v1/privacy", headers=h).json()
    assert fresh["review_required"] is True
    assert fresh["effective_progress_tracking_enabled"] is False
    assert fresh["effective_cloud_tts_enabled"] is False

    toggled = client.put("/v1/privacy", json=_put_body(
        progress_tracking_enabled=True,
        cloud_tts_enabled=True,
    ), headers=h).json()
    assert toggled["review_required"] is False
    assert toggled["effective_progress_tracking_enabled"] is True
    assert toggled["effective_cloud_tts_enabled"] is True

    off = client.put("/v1/privacy", json=_put_body(), headers=h).json()
    assert off["accepted_policy_version"] == "2026-09-26"
    assert off["review_required"] is False
    assert off["progress_tracking_enabled"] is False
    assert off["effective_progress_tracking_enabled"] is False
    assert off["effective_cloud_tts_enabled"] is False


def test_get_summary_counts(client, db):
    h = _auth(client, "p-privacy-counts")
    user_id = _user_id(h)
    now = datetime.now(timezone.utc)

    db.add(ChildProfile(
        id="p-privacy-counts-profile",
        user_id=user_id,
        nickname=None,
        age_band="3-4",
        language_code="en",
        bedtime_mode_default=False,
        microphone_enabled=False,
        ar_enabled=True,
        created_at=now,
        updated_at=now,
    ))
    db.add(Story(
        id="p-privacy-counts-story",
        title="counts",
        slug="p-privacy-counts-story",
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

    body = client.get("/v1/privacy", headers=h).json()

    assert body["counts"] == {
        "child_profiles": 1,
        "authored_stories": 1,
        "story_sessions": 0,
        "interaction_events": 0,
    }


def test_get_recreates_default_row_after_deletion(client, db):
    h = _auth(client, "p-privacy-recreate")
    user_id = _user_id(h)
    client.put("/v1/privacy", json=_put_body(
        progress_tracking_enabled=True,
    ), headers=h)
    assert db.get(PrivacySettings, user_id) is not None

    db.execute(delete(PrivacySettings).where(PrivacySettings.user_id == user_id))
    db.expire_all()
    assert db.get(PrivacySettings, user_id) is None

    body = client.get("/v1/privacy", headers=h).json()

    assert body["accepted_policy_version"] is None
    assert body["core_storage_accepted_at"] is None
    assert body["review_required"] is True
    assert body["progress_tracking_enabled"] is False
    assert body["cloud_tts_enabled"] is False
    assert body["effective_progress_tracking_enabled"] is False
    assert body["effective_cloud_tts_enabled"] is False

    db.expire_all()
    row = db.get(PrivacySettings, user_id)
    assert row is not None
    assert row.accepted_policy_version is None
    assert row.core_storage_accepted_at is None
    assert row.progress_tracking_enabled is False
    assert row.cloud_tts_enabled is False
