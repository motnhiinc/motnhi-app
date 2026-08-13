from functools import lru_cache

from openai import OpenAI

from app.config import settings


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
        try:
            response = self._client.audio.speech.create(
                model=settings.openai_tts_model,
                voice=settings.openai_tts_voice,
                input=text,
                response_format="mp3",
            )
            return response.content
        except Exception as error:
            raise TtsUpstreamError("OpenAI speech request failed") from error


@lru_cache
def get_openai_tts_service() -> OpenAiTtsService:
    return OpenAiTtsService()
