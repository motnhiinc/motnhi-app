"""Paid, opt-in full-page TTS benchmark. Never prints or saves source text/audio."""
import argparse
from statistics import median
from time import monotonic

from app.config import settings
from app.services.page_audio import generate_bundle
from app.services.tts import TtsUpstreamError, get_elevenlabs_tts_service
from verify_scan_configuration import verify

# Distinct synthetic lines: exercise full-page generation, not duplicate reuse.
LINES = [
    "Buổi sáng, chú thỏ thức dậy trong khu rừng xanh.",
    "Ánh nắng nhẹ nhàng chiếu qua những tán lá.",
    "Chú nhìn thấy một chú chim nhỏ bên cửa sổ.",
    "Chim hót líu lo và mời thỏ đi dạo cùng mình.",
    "Hai người bạn bước trên con đường đầy hoa.",
    "Một chú bướm vàng bay qua trước mặt họ.",
    "Thỏ dừng lại ngắm những giọt sương trên cỏ.",
    "Dòng suối trong veo chảy qua những viên đá nhỏ.",
    "Bên kia dòng suối, sóc đang nhặt những hạt dẻ.",
    "Sóc vui vẻ vẫy tay chào hai người bạn.",
    "Cả ba cùng ngồi nghỉ dưới một gốc cây lớn.",
    "Họ kể cho nhau nghe những câu chuyện thú vị.",
    "Đến chiều, thỏ trở về nhà với một nụ cười.",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Required: authorize billable ElevenLabs requests.")
    parser.add_argument("--runs", type=int, default=3, choices=range(1, 21), metavar="1..20")
    args = parser.parse_args()
    if not args.live:
        parser.error("--live is required; each run generates 13 billable clips")
    verify()
    print(f"model={settings.elevenlabs_model_id} concurrency={settings.page_audio_concurrency} lines={len(LINES)} target_ms=1000")
    service = get_elevenlabs_tts_service()
    timings = []
    try:
        for run in range(args.runs):
            started = monotonic()
            bundle = generate_bundle(service, LINES, "vi")
            elapsed_ms = (monotonic() - started) * 1000
            timings.append(elapsed_ms)
            print(f"run={run + 1} complete_bundle_ms={elapsed_ms:.0f} bytes={len(bundle)} target_met={elapsed_ms <= 1000}")
    except TtsUpstreamError as error:
        raise SystemExit(f"Benchmark failed: {error.reason}") from None
    finally:
        service.close()
    print(f"best_ms={min(timings):.0f} median_ms={median(timings):.0f} worst_ms={max(timings):.0f}")


if __name__ == "__main__":
    main()
