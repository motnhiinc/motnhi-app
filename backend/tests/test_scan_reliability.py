from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from io import BytesIO
from threading import Barrier, Lock
from time import sleep, monotonic
from zipfile import ZipFile

import jwt
import pytest

from app.config import settings
from app.services import page_approval, page_audio
from app.services.tts import TtsUpstreamError


def test_language_binding_legacy_and_verified_expiry():
    lines = ["Chú thỏ đi chơi."]
    legacy = page_approval.issue_approval("u", "p", lines)
    assert page_approval.verify_approval(legacy, "u", "p", lines)
    assert not page_approval.verify_approval(legacy, "u", "p", lines, "vi")
    proof = page_approval.issue_approval("u", "p", lines, "vi")
    assert page_approval.verify_approval(proof, "u", "p", lines, "vi")
    assert not page_approval.verify_approval(proof, "u", "p", lines, "en")
    assert not page_approval.verify_approval(proof, "u", "p", lines)
    claims = jwt.decode(proof, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    claims["exp"] = datetime.now(timezone.utc).timestamp() - 1
    expired = jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    assert page_approval.approval_reason(expired, "u", "p", lines, "vi") == "page_approval_expired"
    assert page_approval.approval_reason(expired, "other", "p", lines, "vi") == "page_approval_invalid"
    assert not page_approval.verify_approval(expired, "u", "p", lines, "vi")


def test_parallel_order_and_process_ceiling(monkeypatch):
    monkeypatch.setattr(settings, "page_audio_concurrency", 3)
    monkeypatch.setattr(settings, "page_audio_process_concurrency", 2)
    page_audio.process_slots.cache_clear()
    active = peak = 0
    lock = Lock()
    class Service:
        def generate(self, text):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            sleep(.03 if text == "0" else .01)
            with lock: active -= 1
            return text.encode()
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(page_audio.generate_bundle, Service(), ["0", "1", "2", "3"]) for _ in range(2)]
            for future in futures:
                with ZipFile(BytesIO(future.result())) as archive:
                    assert archive.namelist() == [f"{i:03d}.mp3" for i in range(4)]
                    assert [archive.read(name) for name in archive.namelist()] == [b"0", b"1", b"2", b"3"]
        assert peak == 2
    finally: page_audio.process_slots.cache_clear()


def test_six_parallel_clips_preserve_bundle_order(monkeypatch):
    monkeypatch.setattr(settings, "page_audio_concurrency", 6)
    monkeypatch.setattr(settings, "page_audio_process_concurrency", 6)
    page_audio.process_slots.cache_clear()
    wave = Barrier(6, timeout=5)
    lines = [str(index) for index in range(12)]

    class Service:
        def generate(self, text):
            # Every wave must have six active requests before any can finish.
            wave.wait()
            return text.encode()

    try:
        with ZipFile(BytesIO(page_audio.generate_bundle(Service(), lines))) as archive:
            assert archive.namelist() == [f"{i:03d}.mp3" for i in range(12)]
            assert [archive.read(name) for name in archive.namelist()] == [line.encode() for line in lines]
    finally:
        page_audio.process_slots.cache_clear()


def test_duplicate_clips_are_reused_only_within_request_and_language():
    calls = []

    class Service:
        def generate(self, text, language, **kwargs):
            calls.append((text, language))
            return f"{text}:{language}".encode()

    lines = ["Reading", "Reading", "Reading"]
    languages = ["en", "en", "vi"]
    for _ in range(2):
        audio = page_audio.generate_bundle(Service(), lines, segment_languages=languages)
        with ZipFile(BytesIO(audio)) as archive:
            assert [archive.read(name) for name in archive.namelist()] == [b"Reading:en", b"Reading:en", b"Reading:vi"]
    assert sorted(calls) == [("Reading", "en"), ("Reading", "en"), ("Reading", "vi"), ("Reading", "vi")]


def test_deadline_queue_retry_and_byte_limits(monkeypatch):
    monkeypatch.setattr(settings, "page_audio_deadline_seconds", .02)
    class Slow:
        def generate(self, text): sleep(.06); return b"mp3"
    started = monotonic()
    with pytest.raises(TtsUpstreamError) as caught:
        page_audio.generate_bundle(Slow(), ["a"])
    assert caught.value.reason == "provider_timeout"
    assert monotonic() - started < .05
    sleep(.07)  # Let this controlled unavoidable in-flight fake settle.
    monkeypatch.setattr(settings, "page_audio_deadline_seconds", 1)
    monkeypatch.setattr(settings, "page_audio_queue_seconds", .01)
    slots = page_audio.process_slots()
    for _ in range(settings.page_audio_process_concurrency): slots.acquire()
    try:
        with pytest.raises(TtsUpstreamError) as caught: page_audio.generate_bundle(Slow(), ["a"])
        assert caught.value.reason == "provider_capacity"
    finally:
        for _ in range(settings.page_audio_process_concurrency): slots.release()
    class Transient:
        calls = 0
        def generate(self, text):
            self.calls += 1
            if self.calls == 1: raise TtsUpstreamError("bounded", "provider_unavailable")
            return b"mp3"
    service = Transient()
    page_audio.generate_bundle(service, ["a"])
    assert service.calls == 2
    monkeypatch.setattr(page_audio, "MAX_BUNDLE", 260)
    with pytest.raises(TtsUpstreamError) as caught: page_audio.generate_bundle(service, ["a", "b"])
    assert caught.value.reason == "invalid_audio_bundle"
