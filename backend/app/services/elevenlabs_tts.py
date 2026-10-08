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

logger = logging.getLogger(__name__)
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
            raise TtsUpstreamError("ElevenLabs API key is not configured")
        if not re.fullmatch(r"[A-Za-z0-9]{20,64}", settings.elevenlabs_voice_id):
            raise TtsUpstreamError("ElevenLabs voice ID is invalid")
        if not re.fullmatch(r"[a-z0-9_]{1,64}", settings.elevenlabs_model_id):
            raise TtsUpstreamError("ElevenLabs model ID is invalid")
        if (not math.isfinite(settings.elevenlabs_tts_timeout_seconds)
                or settings.elevenlabs_tts_timeout_seconds <= 0):
            raise TtsUpstreamError("ElevenLabs timeout is invalid")

    def generate(self, text: str) -> bytes:
        if not text.strip() or len(text) > 5000:
            raise TtsUpstreamError("invalid narration text")
        started = monotonic()
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
                if not 200 <= response.status < 300:
                    raise TtsUpstreamError("ElevenLabs speech request failed")
                audio = response.read(MAX_CLIP_BYTES + 1)
            if not audio or len(audio) > MAX_CLIP_BYTES or not (
                audio.startswith(b"ID3") or (len(audio) > 1 and audio[0] == 0xFF and audio[1] & 0xE0 == 0xE0)
            ):
                raise TtsUpstreamError("invalid ElevenLabs audio")
            return audio
        except Exception as error:
            logger.warning(
                "ElevenLabs speech failed: error_type=%s, status=%s, elapsed_seconds=%.3f",
                type(error).__name__,
                getattr(error, "status", None),
                monotonic() - started,
            )
            raise TtsUpstreamError("ElevenLabs speech request failed") from error


@lru_cache
def get_elevenlabs_tts_service() -> ElevenLabsTtsService:
    return ElevenLabsTtsService()
