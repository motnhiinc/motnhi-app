"""Deployment check: uv run python verify_scan_configuration.py [--provider-smoke-test]."""
import argparse
import inspect
from openai.resources.audio.speech import Speech

from app.config import settings
from app.services.tts import get_openai_tts_service


def verify() -> None:
    if settings.page_language_instructions_enabled and not settings.openai_tts_model.startswith("gpt-4o-mini-tts"):
        raise SystemExit("Scan deployment rejected: explicit-language narration requires gpt-4o-mini-tts (including dated versions).")
    if settings.page_language_instructions_enabled and "instructions" not in inspect.signature(Speech.create).parameters:
        raise SystemExit("Scan deployment rejected: installed OpenAI SDK does not support speech instructions.")
    if settings.page_audio_queue_seconds >= settings.page_audio_deadline_seconds:
        raise SystemExit("Scan deployment rejected: queue budget must be shorter than the page deadline.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider-smoke-test", action="store_true", help="Sends two short ground-truth speech requests; discard returned clips.")
    arguments = parser.parse_args()
    verify()
    if arguments.provider_smoke_test:
        service = get_openai_tts_service()
        for language, text in [("vi", "Chú thỏ ngắm những chiếc lá xanh."), ("en", "The little rabbit looks at green leaves.")]:
            if not service.generate(text, language):
                raise SystemExit("Scan deployment rejected: empty speech response.")
    print("Scan configuration verified. Physical Vietnamese listening acceptance remains required.")
