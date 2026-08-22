from dataclasses import dataclass

from app.main import app
from app.routers import tts as tts_router
from app.routers.tts import get_tts_service
from app.services.tts import TtsUpstreamError


def _auth(client):
    token = client.post("/v1/auth/device", json={"device_id": "tts-device"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


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


def test_tts_requires_auth(client):
    assert client.post("/v1/tts", json={"text": "Hello"}).status_code == 401


def test_tts_rejects_empty_and_over_limit_without_upstream_call(client):
    fake = FakeTtsService()
    app.dependency_overrides[get_tts_service] = lambda: fake
    headers = _auth(client)
    try:
        assert client.post("/v1/tts", json={"text": "   "}, headers=headers).status_code == 422
        assert client.post("/v1/tts", json={"text": "x" * 4001}, headers=headers).status_code == 422
        assert fake.calls == []
    finally:
        app.dependency_overrides.pop(get_tts_service, None)


def test_tts_forwards_mixed_text_once_and_returns_non_cacheable_mp3(client):
    fake = FakeTtsService()
    app.dependency_overrides[get_tts_service] = lambda: fake
    text = "The moon is bright. Một đêm thật đẹp."
    try:
        response = client.post("/v1/tts", json={"text": text}, headers=_auth(client))
        assert response.status_code == 200
        assert response.content == b"ID3demo"
        assert response.headers["content-type"] == "audio/mpeg"
        assert response.headers["cache-control"] == "no-store"
        assert fake.calls == [text]
    finally:
        app.dependency_overrides.pop(get_tts_service, None)


def test_tts_maps_upstream_failure_without_leaking_details(client):
    fake = FakeTtsService(error=TtsUpstreamError("secret upstream detail"))
    app.dependency_overrides[get_tts_service] = lambda: fake
    try:
        response = client.post("/v1/tts", json={"text": "Hello"}, headers=_auth(client))
        assert response.status_code == 502
        assert response.json() == {"detail": "narration generation failed"}
        assert "secret upstream detail" not in response.text
    finally:
        app.dependency_overrides.pop(get_tts_service, None)


def test_tts_maps_service_construction_failure_without_leaking_details(client, monkeypatch):
    def fail_to_construct():
        raise TtsUpstreamError("secret configuration detail")

    monkeypatch.setattr(tts_router, "get_openai_tts_service", fail_to_construct)

    response = client.post("/v1/tts", json={"text": "Hello"}, headers=_auth(client))

    assert response.status_code == 502
    assert response.json() == {"detail": "narration generation failed"}
    assert "secret configuration detail" not in response.text
