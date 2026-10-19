import json

import httpx
import pytest

from app.config import settings
from app.services import tts


@pytest.fixture
def speech(monkeypatch):
    monkeypatch.setattr(settings, "elevenlabs_tts_debug_logging", False)
    monkeypatch.setattr(settings, "elevenlabs_api_key", "private-key")
    monkeypatch.setattr(settings, "elevenlabs_voice_id", "test-voice")
    monkeypatch.setattr(settings, "elevenlabs_model_id", "eleven_flash_v2_5")
    service = tts.ElevenLabsTtsService()
    service._client.close()
    yield service
    service.close()


def transport(service, handler):
    service._client = httpx.Client(
        base_url="https://api.elevenlabs.io/v1/",
        headers={"xi-api-key": "private-key"},
        transport=httpx.MockTransport(handler),
    )


@pytest.mark.parametrize("language", [None, "vi", "en", "mixed"])
def test_exact_text_language_and_low_latency_settings(speech, language):
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(200, content=b"mp3", headers={"content-type": "audio/mpeg"})

    transport(speech, handler)
    text = "Chú thỏ, tiếng Việt! Reading 123."
    assert speech.generate(text, language, timeout=.5) == b"mp3"
    request, = requests
    assert request.url.path == "/v1/text-to-speech/test-voice"
    assert request.url.params["output_format"] == "mp3_44100_64"
    assert request.headers["xi-api-key"] == "private-key"
    payload = json.loads(request.content)
    assert payload["text"] == text
    assert payload["model_id"] == "eleven_flash_v2_5"
    assert payload["voice_settings"] == {"style": 0, "use_speaker_boost": False}
    assert payload.get("language_code") == (language if language in {"en", "vi"} else None)
    assert request.extensions["timeout"]["read"] == .5


@pytest.mark.parametrize("status,reason", [(401, "provider_failed"), (422, "provider_failed"), (429, "provider_capacity"), (503, "provider_unavailable")])
def test_errors_are_safe_and_not_implicitly_retried(speech, status, reason):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(status, text="private provider response")

    transport(speech, handler)
    with pytest.raises(tts.TtsUpstreamError) as caught:
        speech.generate("private child text")
    assert caught.value.reason == reason
    assert "private" not in str(caught.value)
    assert len(calls) == 1


@pytest.mark.parametrize("content,content_type", [(b"", "audio/mpeg"), (b"{}", "application/json"), (b"1234", "audio/mpeg")])
def test_invalid_and_oversized_audio_is_rejected(speech, monkeypatch, content, content_type):
    monkeypatch.setattr(tts, "MAX_AUDIO_BYTES", 3)
    transport(speech, lambda request: httpx.Response(200, content=content, headers={"content-type": content_type}))
    with pytest.raises(tts.TtsUpstreamError) as caught:
        speech.generate("text")
    assert caught.value.reason == "invalid_audio_bundle"


def test_timeout_and_connection_failures(speech):
    for error, reason in [(httpx.ReadTimeout("private"), "provider_timeout"), (httpx.ConnectError("private"), "provider_unavailable")]:
        def handler(request):
            raise error
        transport(speech, handler)
        with pytest.raises(tts.TtsUpstreamError) as caught:
            speech.generate("text")
        assert caught.value.reason == reason
        speech.close()


def test_missing_key_fails_before_network(monkeypatch):
    monkeypatch.setattr(settings, "elevenlabs_api_key", "")
    with pytest.raises(tts.TtsUpstreamError) as caught:
        tts.ElevenLabsTtsService()
    assert caught.value.reason == "speech_configuration_invalid"


@pytest.mark.parametrize("debug", [False, True])
def test_request_and_provider_error_logging(speech, monkeypatch, caplog, debug):
    monkeypatch.setattr(settings, "elevenlabs_tts_debug_logging", debug)
    transport(speech, lambda request: httpx.Response(
        503, json={"detail": "provider diagnostic"}, headers={"request-id": "upstream-123"},
    ))
    with caplog.at_level("INFO", logger="uvicorn.error.tts"):
        with pytest.raises(tts.TtsUpstreamError):
            speech.generate("Private narration\nTiếng Việt", "vi", timeout=.5)
    request = next(json.loads(record.message.split(" ", 1)[1]) for record in caplog.records
                   if record.message.startswith("tts_request "))
    failure = next(json.loads(record.message.split(" ", 1)[1]) for record in caplog.records
                   if record.message.startswith("tts_failed "))
    assert request["payload"]["model_id"] == "eleven_flash_v2_5"
    assert request["payload"]["language_code"] == "vi"
    assert request["params"] == {"output_format": "mp3_44100_64"}
    assert request["timeout_seconds"] == .5
    assert ("text" in request["payload"]) is debug
    assert ("provider diagnostic" in caplog.text) is debug
    assert "private-key" not in caplog.text
    assert failure["status_code"] == 503
    assert failure["reason"] == "provider_unavailable"
    assert failure["provider_request_id"] == "upstream-123"
    assert failure["request_id"] == request["request_id"]


def test_debug_error_body_is_bounded(speech, monkeypatch, caplog):
    monkeypatch.setattr(settings, "elevenlabs_tts_debug_logging", True)
    transport(speech, lambda request: httpx.Response(503, content=b"x" * 10000))
    with caplog.at_level("INFO", logger="uvicorn.error.tts"):
        with pytest.raises(tts.TtsUpstreamError):
            speech.generate("text")
    diagnostic = next(json.loads(record.message.split(" ", 1)[1]) for record in caplog.records
                      if record.message.startswith("tts_provider_error "))
    assert len(diagnostic["body_preview"]) == 4096
