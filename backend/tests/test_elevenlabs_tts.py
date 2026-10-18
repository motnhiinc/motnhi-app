import json

import httpx
import pytest

from app.config import settings
from app.services import tts


@pytest.fixture
def speech(monkeypatch):
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
