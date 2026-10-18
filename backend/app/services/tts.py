"""ElevenLabs speech adapter with a shared, thread-safe connection pool."""
from functools import lru_cache
from time import monotonic

import httpx

from app.config import settings

MAX_AUDIO_BYTES = 2 * 1024 * 1024


class TtsUpstreamError(RuntimeError):
    def __init__(self, message: str, reason: str = "provider_failed") -> None:
        super().__init__(message)
        self.reason = reason


def provider_reason(error: Exception) -> str:
    if isinstance(error, TtsUpstreamError):
        return error.reason
    if isinstance(error, httpx.TimeoutException):
        return "provider_timeout"
    if isinstance(error, httpx.HTTPStatusError):
        if error.response.status_code == 429:
            return "provider_capacity"
        if error.response.status_code >= 500:
            return "provider_unavailable"
    if isinstance(error, httpx.RequestError):
        return "provider_unavailable"
    return "provider_failed"


class ElevenLabsTtsService:
    def __init__(self) -> None:
        if not settings.elevenlabs_api_key or not settings.elevenlabs_voice_id:
            raise TtsUpstreamError("ElevenLabs credentials are not configured", "speech_configuration_invalid")
        self._voice_id = settings.elevenlabs_voice_id
        self._model_id = settings.elevenlabs_model_id
        self._output_format = settings.elevenlabs_output_format
        # Reuse TCP/TLS connections across lines and pages; never retry implicitly.
        self._client = httpx.Client(
            base_url="https://api.elevenlabs.io/v1/",
            headers={"xi-api-key": settings.elevenlabs_api_key, "Accept": "audio/mpeg"},
            timeout=settings.elevenlabs_tts_timeout_seconds,
            limits=httpx.Limits(max_connections=64, max_keepalive_connections=64, keepalive_expiry=60),
        )

    def generate(self, text: str, content_language: str | None = None, *, timeout: float | None = None) -> bytes:
        if content_language not in {None, "vi", "en", "mixed"}:
            raise TtsUpstreamError("unsupported speech language", "speech_configuration_invalid")
        payload = {
            "text": text,
            "model_id": self._model_id,
            "voice_settings": {"style": 0, "use_speaker_boost": False},
        }
        # Do not force mixed passages into a single language or rewrite input.
        if content_language in {"vi", "en"}:
            payload["language_code"] = content_language
        budget = min(timeout, settings.elevenlabs_tts_timeout_seconds) if timeout is not None else settings.elevenlabs_tts_timeout_seconds
        deadline = monotonic() + budget
        try:
            with self._client.stream(
                "POST", f"text-to-speech/{self._voice_id}",
                params={"output_format": self._output_format}, json=payload, timeout=budget,
            ) as response:
                response.raise_for_status()
                if not response.headers.get("content-type", "").lower().startswith("audio/"):
                    raise TtsUpstreamError("unexpected speech response", "invalid_audio_bundle")
                audio = bytearray()
                for chunk in response.iter_bytes():
                    if monotonic() >= deadline:
                        raise TtsUpstreamError("speech deadline exceeded", "provider_timeout")
                    if len(audio) + len(chunk) > MAX_AUDIO_BYTES:
                        raise TtsUpstreamError("speech response too large", "invalid_audio_bundle")
                    audio.extend(chunk)
                if not audio:
                    raise TtsUpstreamError("empty speech response", "invalid_audio_bundle")
                return bytes(audio)
        except TtsUpstreamError:
            raise
        except Exception as error:
            raise TtsUpstreamError("ElevenLabs speech request failed", provider_reason(error)) from error

    def close(self) -> None:
        self._client.close()


@lru_cache
def get_elevenlabs_tts_service() -> ElevenLabsTtsService:
    return ElevenLabsTtsService()
