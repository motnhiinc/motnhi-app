from functools import lru_cache

import httpx
from openai import OpenAI
from openai import APITimeoutError, RateLimitError, APIConnectionError, InternalServerError

from app.config import settings


class TtsUpstreamError(RuntimeError):
    def __init__(self, message: str, reason: str = "provider_failed") -> None:
        super().__init__(message)
        self.reason = reason


def provider_reason(error: Exception) -> str:
    if isinstance(error, (APITimeoutError, httpx.TimeoutException)):
        return "provider_timeout"
    if isinstance(error, RateLimitError):
        return "provider_capacity"
    if isinstance(error, httpx.HTTPStatusError):
        if error.response.status_code == 429:
            return "provider_capacity"
        if error.response.status_code >= 500:
            return "provider_unavailable"
    if isinstance(error, httpx.RequestError):
        return "provider_unavailable"
    if isinstance(error, (APIConnectionError, InternalServerError)):
        return "provider_unavailable"
    return "provider_failed"


class OpenAiTtsService:
    def __init__(self) -> None:
        if not settings.openai_api_key:
            raise TtsUpstreamError("OPENAI_API_KEY is not configured")
        self._client = OpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.openai_tts_timeout_seconds,
            max_retries=0,
        )

    def generate(self, text: str, content_language: str | None = None, *, timeout: float | None = None) -> bytes:
        options = {}
        if content_language is not None:
            if not settings.page_language_instructions_enabled or not settings.openai_tts_model.startswith("gpt-4o-mini-tts"):
                raise TtsUpstreamError("instruction-capable speech configuration required", "speech_configuration_invalid")
            language = {"vi": "Vietnamese", "en": "English", "mixed": "mixed Vietnamese and English"}[content_language]
            options["instructions"] = (
                f"Read the supplied {language} text faithfully with natural {language} pronunciation "
                "and child-friendly pacing. Preserve all words. Do not translate or add words."
                " For mixed-language passages, pronounce each passage in its original language."
            )
        try:
            client = self._client if timeout is None else self._client.with_options(timeout=timeout)
            response = client.audio.speech.create(
                model=settings.openai_tts_model,
                voice=settings.openai_tts_voice,
                input=text,
                response_format="mp3",
                **options,
            )
            return response.content
        except Exception as error:
            raise TtsUpstreamError("OpenAI speech request failed", provider_reason(error)) from error


@lru_cache
def get_openai_tts_service() -> OpenAiTtsService:
    return OpenAiTtsService()
