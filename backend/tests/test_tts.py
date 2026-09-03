from dataclasses import dataclass
from datetime import datetime, timezone

import pytest

from app.auth import decode_token
from app.models import PrivacySettings
from app.routers import tts as tts_router
from app.services.tts import TtsUpstreamError

POLICY_VERSION = "2026-08-28"


def _auth(client, device_id="tts-device"):
    token = client.post("/v1/auth/device", json={"device_id": device_id}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _uid(headers):
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _write_consent(db, user_id, *, cloud_tts_enabled, policy_version=POLICY_VERSION):
    now = datetime.now(timezone.utc)
    db.add(PrivacySettings(
        user_id=user_id,
        accepted_policy_version=policy_version,
        core_storage_accepted_at=now,
        progress_tracking_enabled=False,
        cloud_tts_enabled=cloud_tts_enabled,
        last_active_at=now,
        updated_at=now,
    ))
    db.flush()


@dataclass
class FakeTtsService:
    audio: bytes = b"ID3demo"
    error: Exception | None = None
    calls: list[str] | None = None

    def __post_init__(self):
        self.calls = []

    def generate(self, text: str) -> bytes:
        self.calls.append(text)
        if self.error is not None:
            raise self.error
        return self.audio


def _counting_factory(constructions, fake):
    def factory():
        constructions.append(True)
        return fake

    return factory


@pytest.mark.parametrize(
    ("device_id", "consent_kwargs"),
    [
        ("tts-no-consent-device", None),
        ("tts-revoked-device", {"cloud_tts_enabled": False}),
        ("tts-stale-device", {"cloud_tts_enabled": True, "policy_version": "2026-01-01"}),
    ],
)
def test_tts_without_effective_cloud_consent_never_constructs_service(
    client, db, monkeypatch, device_id, consent_kwargs
):
    constructions = []
    fake = FakeTtsService()
    monkeypatch.setattr(
        tts_router, "get_openai_tts_service", _counting_factory(constructions, fake)
    )
    headers = _auth(client, device_id)
    if consent_kwargs is not None:
        _write_consent(db, _uid(headers), **consent_kwargs)

    response = client.post("/v1/tts", json={"text": "Hello"}, headers=headers)

    assert response.status_code == 403
    assert response.json() == {"detail": "cloud_tts_disabled"}
    assert constructions == []
    assert fake.calls == []


def test_tts_with_current_cloud_consent_constructs_service_once_and_generates(
    client, db, monkeypatch
):
    constructions = []
    fake = FakeTtsService()
    monkeypatch.setattr(
        tts_router, "get_openai_tts_service", _counting_factory(constructions, fake)
    )
    headers = _auth(client, "tts-enabled-device")
    _write_consent(db, _uid(headers), cloud_tts_enabled=True)
    text = "The moon is bright."

    response = client.post("/v1/tts", json={"text": text}, headers=headers)

    assert response.status_code == 200
    assert response.content == b"ID3demo"
    assert constructions == [True]
    assert fake.calls == [text]


def test_tts_requires_auth(client):
    assert client.post("/v1/tts", json={"text": "Hello"}).status_code == 401


def test_tts_rejects_empty_and_over_limit_without_upstream_call(client, monkeypatch):
    fake = FakeTtsService()
    monkeypatch.setattr(tts_router, "get_tts_service", lambda: fake)
    headers = _auth(client)
    assert client.post("/v1/tts", json={"text": "   "}, headers=headers).status_code == 422
    assert client.post("/v1/tts", json={"text": "x" * 4001}, headers=headers).status_code == 422
    assert fake.calls == []


def test_tts_forwards_mixed_text_once_and_returns_non_cacheable_mp3(client, monkeypatch):
    fake = FakeTtsService()
    monkeypatch.setattr(tts_router, "get_tts_service", lambda: fake)
    text = "The moon is bright. Một đêm thật đẹp."
    response = client.post("/v1/tts", json={"text": text}, headers=_auth(client))
    assert response.status_code == 200
    assert response.content == b"ID3demo"
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.headers["cache-control"] == "no-store"
    assert fake.calls == [text]


def test_tts_maps_upstream_failure_without_leaking_details(client, monkeypatch):
    fake = FakeTtsService(error=TtsUpstreamError("secret upstream detail"))
    monkeypatch.setattr(tts_router, "get_tts_service", lambda: fake)
    response = client.post("/v1/tts", json={"text": "Hello"}, headers=_auth(client))
    assert response.status_code == 502
    assert response.json() == {"detail": "narration generation failed"}
    assert "secret upstream detail" not in response.text


def test_tts_maps_service_construction_failure_without_leaking_details(client, monkeypatch):
    def fail_to_construct():
        raise TtsUpstreamError("secret configuration detail")

    monkeypatch.setattr(tts_router, "get_openai_tts_service", fail_to_construct)

    response = client.post("/v1/tts", json={"text": "Hello"}, headers=_auth(client))

    assert response.status_code == 502
    assert response.json() == {"detail": "narration generation failed"}
    assert "secret configuration detail" not in response.text
