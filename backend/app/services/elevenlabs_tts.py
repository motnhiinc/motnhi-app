"""One bounded ElevenLabs MP3 request per approved scanned-page line."""

import json
import logging
import math
import re
from functools import lru_cache
from time import monotonic
from urllib.request import HTTPRedirectHandler, Request, build_opener

from app.config import settings
from app.services.tts import TtsUpstreamError

logger = logging.getLogger(f"uvicorn.error.{__name__}")
MAX_CLIP_BYTES = 2 * 1024 * 1024


class _NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        # Never forward xi-api-key to a URL supplied by an upstream redirect.
        return None


def _open(request: Request, timeout: float):
    return build_opener(_NoRedirects()).open(request, timeout=timeout)


class ElevenLabsTtsService:
    def __init__(self) -> None:
        if not settings.elevenlabs_api_key.strip():
            logger.warning("ElevenLabs initialization failed: code=missing_api_key, setting=ELEVENLABS_API_KEY")
            raise TtsUpstreamError("ElevenLabs API key is not configured")
        if not re.fullmatch(r"[A-Za-z0-9]{20,64}", settings.elevenlabs_voice_id):
            logger.warning("ElevenLabs initialization failed: code=invalid_voice_id, setting=ELEVENLABS_VOICE_ID")
            raise TtsUpstreamError("ElevenLabs voice ID is invalid")
        if not re.fullmatch(r"[a-z0-9_]{1,64}", settings.elevenlabs_model_id):
            logger.warning("ElevenLabs initialization failed: code=invalid_model_id, setting=ELEVENLABS_MODEL_ID")
            raise TtsUpstreamError("ElevenLabs model ID is invalid")
        if (not math.isfinite(settings.elevenlabs_tts_timeout_seconds)
                or settings.elevenlabs_tts_timeout_seconds <= 0):
            logger.warning("ElevenLabs initialization failed: code=invalid_timeout, setting=ELEVENLABS_TTS_TIMEOUT_SECONDS")
            raise TtsUpstreamError("ElevenLabs timeout is invalid")

    def generate(self, text: str, *, request_id: str | None = None, clip_number: int | None = None) -> bytes:
        if not text.strip() or len(text) > 5000:
            raise TtsUpstreamError("invalid narration text")
        started = monotonic()
        headers_seconds = None
        body_seconds = None
        status = None
        audio_bytes = 0
        logger.info(
            "ElevenLabs speech started: request_id=%s, clip_number=%s, chars=%s",
            request_id, clip_number, len(text),
        )
        request = Request(
            f"https://api.elevenlabs.io/v1/text-to-speech/{settings.elevenlabs_voice_id}"
            "?output_format=mp3_44100_128",
            data=json.dumps({"text": text, "model_id": settings.elevenlabs_model_id}, ensure_ascii=False).encode("utf-8"),
            headers={
                "xi-api-key": settings.elevenlabs_api_key,
                "Content-Type": "application/json",
                "Accept": "audio/mpeg",
            },
            method="POST",
        )
        try:
            with _open(request, timeout=settings.elevenlabs_tts_timeout_seconds) as response:
                headers_received = monotonic()
                headers_seconds = headers_received - started
                status = response.status
                if not 200 <= response.status < 300:
                    raise TtsUpstreamError("ElevenLabs speech request failed")
                audio = response.read(MAX_CLIP_BYTES + 1)
                body_seconds = monotonic() - headers_received
                audio_bytes = len(audio)
            if not audio or len(audio) > MAX_CLIP_BYTES or not (
                audio.startswith(b"ID3") or (len(audio) > 1 and audio[0] == 0xFF and audio[1] & 0xE0 == 0xE0)
            ):
                raise TtsUpstreamError("invalid ElevenLabs audio")
            logger.info(
                "ElevenLabs speech completed: request_id=%s, clip_number=%s, chars=%s, "
                "status=%s, headers_seconds=%.3f, body_seconds=%.3f, audio_bytes=%s, elapsed_seconds=%.3f",
                request_id, clip_number, len(text), status, headers_seconds, body_seconds,
                audio_bytes, monotonic() - started,
            )
            return audio
        except Exception as error:
            logger.warning(
                "ElevenLabs speech failed: error_type=%s, status=%s, elapsed_seconds=%.3f, "
                "request_id=%s, clip_number=%s, chars=%s, headers_seconds=%s, body_seconds=%s, audio_bytes=%s",
                type(error).__name__,
                getattr(error, "code", getattr(error, "status", status)),
                monotonic() - started,
                request_id, clip_number, len(text), headers_seconds, body_seconds, audio_bytes,
            )
            raise TtsUpstreamError("ElevenLabs speech request failed") from error


@lru_cache
def get_elevenlabs_tts_service() -> ElevenLabsTtsService:
    return ElevenLabsTtsService()
