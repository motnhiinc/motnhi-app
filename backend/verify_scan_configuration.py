"""Deployment check: uv run python verify_scan_configuration.py [--provider-smoke-test]."""
import argparse

from app.config import settings
from app.services.tts import get_elevenlabs_tts_service


def verify() -> None:
    if not settings.elevenlabs_api_key or settings.elevenlabs_api_key == "CHANGE_ME":
        raise SystemExit("Scan deployment rejected: ELEVENLABS_API_KEY is required.")
    if not settings.elevenlabs_voice_id or settings.elevenlabs_voice_id == "CHANGE_ME":
        raise SystemExit("Scan deployment rejected: ELEVENLABS_VOICE_ID is required.")
    if settings.page_audio_queue_seconds >= settings.page_audio_deadline_seconds:
        raise SystemExit("Scan deployment rejected: queue budget must be shorter than the page deadline.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider-smoke-test", action="store_true", help="Sends two short ground-truth speech requests; discard returned clips.")
    arguments = parser.parse_args()
    verify()
    if arguments.provider_smoke_test:
        service = get_elevenlabs_tts_service()
        try:
            for language, text in [("vi", "Chú thỏ ngắm những chiếc lá xanh."), ("en", "The little rabbit looks at green leaves.")]:
                if not service.generate(text, language):
                    raise SystemExit("Scan deployment rejected: empty speech response.")
        finally:
            service.close()
    print("Scan configuration verified. Physical Vietnamese listening acceptance remains required.")
