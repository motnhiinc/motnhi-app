import logging
import re
from functools import lru_cache
from time import monotonic

from openai import OpenAI

from app.config import settings

logger = logging.getLogger(__name__)


class TtsUpstreamError(RuntimeError):
    pass


class OpenAiTtsService:
    def __init__(self) -> None:
        if not settings.openai_api_key:
            raise TtsUpstreamError("OPENAI_API_KEY is not configured")
        self._client = OpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.openai_tts_timeout_seconds,
            max_retries=0,
        )

    def generate(self, text: str) -> bytes:
        started = monotonic()
        try:
            response = self._client.audio.speech.create(
                model=settings.openai_tts_model,
                voice=settings.openai_tts_voice,
                input=text,
                response_format="mp3",
            )
            return response.content
        except Exception as error:
            code = getattr(error, "code", None)
            if not isinstance(code, str) or not re.fullmatch(r"[a-z0-9_]{1,64}", code):
                code = "unknown"
            logger.warning(
                "OpenAI speech failed: error_type=%s, status=%s, code=%s, elapsed_seconds=%.3f",
                type(error).__name__,
                getattr(error, "status_code", None),
                code,
                monotonic() - started,
            )
            raise TtsUpstreamError("OpenAI speech request failed") from error


@lru_cache
def get_openai_tts_service() -> OpenAiTtsService:
    return OpenAiTtsService()
