"""Bounded, ephemeral page synthesis. Workers never mutate the ZIP."""
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from functools import lru_cache
from io import BytesIO
from threading import BoundedSemaphore, Event, Lock
from time import monotonic
from zipfile import ZIP_STORED, ZipFile
import logging

from app.config import settings
from app.services.tts import TtsUpstreamError, ElevenLabsTtsService

log = logging.getLogger("uvicorn.error.scan")
MAX_CLIP = 2 * 1024 * 1024
MAX_BUNDLE = 32 * 1024 * 1024


@lru_cache
def process_slots() -> BoundedSemaphore:
    return BoundedSemaphore(max(1, settings.page_audio_process_concurrency))


def generate_bundle(service, lines: list[str], language: str | None = None, *, correlation: str = "", segment_languages: list[str] | None = None) -> bytes:
    if segment_languages is not None and len(segment_languages) != len(lines):
        raise ValueError("invalid segment languages")
    page_started = monotonic()
    deadline = page_started + settings.page_audio_deadline_seconds
    stopped = Event()
    slots = process_slots()
    # Reuse identical clips only inside this request. Never retain child text or
    # generated audio across requests, users, or privacy/deletion boundaries.
    unique = {}
    aliases = {}
    for index, text in enumerate(lines):
        clip_language = segment_languages[index] if segment_languages is not None else language
        key = (text, clip_language)
        original = unique.setdefault(key, index)
        aliases.setdefault(original, []).append(index)
    work = list(unique.values())
    workers = max(1, min(8, settings.page_audio_concurrency, len(work)))
    byte_lock = Lock()
    collected_bytes = 0

    def synthesize(index):
        nonlocal collected_bytes
        queued = monotonic()
        if not slots.acquire(timeout=max(0, min(settings.page_audio_queue_seconds, deadline - queued))):
            stopped.set()
            raise TtsUpstreamError("queue budget exceeded", "provider_capacity")
        try:
            log.info("scan_stage %s stage=audio_queue elapsed_ms=%d", correlation, (monotonic() - queued) * 1000)
            for attempt in range(min(1, max(0, settings.page_audio_transient_retries)) + 1):
                remaining = deadline - monotonic()
                if stopped.is_set() or remaining <= 0:
                    raise TtsUpstreamError("page deadline exceeded", "provider_timeout")
                started = monotonic()
                try:
                    # Keep the legacy service contract for old requests/providers.
                    clip_language = segment_languages[index] if segment_languages is not None else language
                    audio = (service.generate(lines[index]) if clip_language is None and not isinstance(service, ElevenLabsTtsService) else
                             service.generate(lines[index], clip_language, timeout=min(remaining, settings.elevenlabs_tts_timeout_seconds)))
                    if stopped.is_set() or monotonic() >= deadline:
                        raise TtsUpstreamError("page generation abandoned", "provider_timeout")
                    if not audio or len(audio) > MAX_CLIP:
                        raise TtsUpstreamError("invalid audio", "invalid_audio_bundle")
                    with byte_lock:
                        collected_bytes += len(audio) * len(aliases[index])
                        if collected_bytes + len(lines) * 128 > MAX_BUNDLE:
                            stopped.set()
                            raise TtsUpstreamError("bundle too large", "invalid_audio_bundle")
                    return audio
                except TtsUpstreamError as error:
                    if attempt >= settings.page_audio_transient_retries or error.reason not in {
                        "provider_timeout", "provider_capacity", "provider_unavailable"
                    }:
                        raise
                finally:
                    log.info("scan_stage %s stage=synthesis index=%d chars=%d retry=%d elapsed_ms=%d", correlation, index, len(lines[index]), attempt, (monotonic() - started) * 1000)
            raise TtsUpstreamError("synthesis failed")
        except Exception:
            stopped.set()
            raise
        finally:
            slots.release()

    pool = ThreadPoolExecutor(max_workers=workers)
    pending = {}
    results = [None] * len(lines)
    next_index = 0
    try:
        while next_index < min(workers, len(work)):
            index = work[next_index]
            pending[pool.submit(synthesize, index)] = index
            next_index += 1
        while pending:
            done, _ = wait(pending, timeout=max(0, deadline - monotonic()), return_when=FIRST_COMPLETED)
            if not done:
                raise TtsUpstreamError("page deadline exceeded", "provider_timeout")
            for future in done:
                index = pending.pop(future)
                audio = future.result()
                for alias in aliases[index]:
                    results[alias] = audio
            for _ in done:
                if next_index < len(work):
                    index = work[next_index]
                    pending[pool.submit(synthesize, index)] = index
                    next_index += 1
        started = monotonic()
        output = BytesIO()
        with ZipFile(output, "w", compression=ZIP_STORED) as archive:
            for index, audio in enumerate(results):
                archive.writestr(f"{index:03d}.mp3", audio)
        if output.tell() > MAX_BUNDLE:
            raise TtsUpstreamError("bundle too large", "invalid_audio_bundle")
        if monotonic() > deadline:
            raise TtsUpstreamError("page deadline exceeded", "provider_timeout")
        log.info("scan_stage %s stage=bundle elapsed_ms=%d", correlation, (monotonic() - started) * 1000)
        log.info("scan_stage %s stage=audio_total line_count=%d unique_clips=%d workers=%d elapsed_ms=%d", correlation, len(lines), len(work), workers, (monotonic() - page_started) * 1000)
        return output.getvalue()
    finally:
        stopped.set()
        for future in pending:
            future.cancel()
        # In-flight calls release their process slot under provider timeouts.
        pool.shutdown(wait=False, cancel_futures=True)
