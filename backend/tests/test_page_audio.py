import base64
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
from zipfile import ZipFile

import pytest
from PIL import Image

from app.auth import decode_token
from app.models import ChildProfile, PrivacySettings
from app.routers import speakable_page
from app.services import page_approval
from app.services.page_validation import ValidationVerdict

POLICY = "2026-10-06"


@pytest.mark.parametrize("fails,status,reason", [
    (False, 200, "recognition_uncertain"),
    (True, 503, "provider_failed"),
])
def test_vision_failure_never_approves_native_ocr(client, db, monkeypatch, fails, status, reason):
    headers = _auth(client, "vision-failure")
    _owned_profile(db, _user(headers), "vision-failure-profile")

    class Ocr:
        def recognize(self, *args):
            if fails:
                raise ValueError("upstream details")
            return []

    monkeypatch.setattr(speakable_page.page_ocr, "GoogleVisionOcr", Ocr)
    response = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": "vision-failure-profile", "image_base64": _image_base64(),
        "content_language": "vi", "ocr_provider": "google_vision", "lines": [_line("Vét")],
    })
    assert response.status_code == status
    assert response.json()["reason"] == reason
    assert "proof" not in response.json()
    assert "recognized_lines" not in response.json()


def test_vision_proof_and_audio_use_recognized_text_and_segment_languages(client, db, monkeypatch):
    headers = _auth(client, "corrected-page")
    user_id = _user(headers)
    _owned_profile(db, user_id, "corrected-profile")
    recognized = [
        {**_line("Bạn Vẹt xanh đáp xuống."), "recognizedLanguage": "vi"},
        {**_line("University of Reading"), "recognizedLanguage": "en"},
    ]

    class Ocr:
        def recognize(self, *args):
            return recognized

    class Validator:
        def validate(self, image, lines, *args):
            assert lines == [line["text"] for line in recognized]
            return ValidationVerdict(text_matches=True, age_suitable=True, certain=True)

    monkeypatch.setattr(speakable_page.page_ocr, "GoogleVisionOcr", Ocr)
    monkeypatch.setattr(speakable_page.page_validation, "OpenAiPageValidator", Validator)
    calls = []

    class Speech:
        def generate(self, text, language, **kwargs):
            calls.append((text, language))
            return b"audio"

    monkeypatch.setattr(speakable_page, "get_openai_tts_service", Speech)
    raw = ["Bạn Vét xanh", "đáp xuống.", "University of Reading"]
    response = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": "corrected-profile", "image_base64": _image_base64(),
        "content_language": "vi", "ocr_provider": "google_vision",
    })
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "approved"
    texts = [line["text"] for line in payload["recognized_lines"]]
    body = {"profile_id": "corrected-profile", "proof": payload["proof"], "content_language": "vi", "lines": raw}
    assert client.post("/v1/speakable-page/audio", headers=headers, json=body).status_code == 403
    assert not calls
    body["lines"] = texts
    audio = client.post("/v1/speakable-page/audio", headers=headers, json=body)
    assert audio.status_code == 200
    assert sorted(calls) == sorted([(texts[0], "vi"), (texts[1], "en")])
    with ZipFile(BytesIO(audio.content)) as bundle:
        assert bundle.namelist() == ["000.mp3", "001.mp3"]


def _auth(client, device):
    token = client.post("/v1/auth/device", json={"device_id": device}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def _user(headers):
    return decode_token(headers["Authorization"].removeprefix("Bearer "))


def _owned_profile(db, user_id, profile_id):
    now = datetime.now(timezone.utc)
    settings = db.get(PrivacySettings, user_id)
    settings.accepted_policy_version = POLICY
    settings.core_storage_accepted_at = now
    settings.cloud_tts_enabled = True
    settings.page_image_validation_enabled = True
    db.add(ChildProfile(
        id=profile_id,
        user_id=user_id,
        nickname=None,
        age_band="5-6",
        language_code="en",
        bedtime_mode_default=False,
        microphone_enabled=False,
        ar_enabled=True,
        created_at=now,
        updated_at=now,
    ))
    db.flush()


def _image_base64():
    image = BytesIO()
    Image.new("RGB", (80, 120), "white").save(image, format="JPEG")
    return base64.b64encode(image.getvalue()).decode("ascii")


def _line(text="A little fox"):
    return {"text": text, "left": 0.1, "top": 0.2, "width": 0.8, "height": 0.1}


@dataclass
class FakeValidator:
    verdict: ValidationVerdict

    def validate(self, image, lines, age_band, content_language=None):
        assert image.startswith(b"\xff\xd8\xff")
        assert age_band == "5-6"
        return self.verdict


@dataclass
class FakeTts:
    fail_on: str | None = None
    calls: list[str] | None = None

    def __post_init__(self):
        self.calls = []

    def generate(self, text, content_language=None, **kwargs):
        self.calls.append(text)
        if text == self.fail_on:
            raise RuntimeError("upstream detail must not escape")
        return f"MP3:{text}".encode()


def test_validate_returns_proof_only_for_explicitly_approved_result(
    client, db, monkeypatch
):
    headers = _auth(client, "page-validation-approved")
    user_id = _user(headers)
    profile_id = "page-validation-profile"
    _owned_profile(db, user_id, profile_id)
    monkeypatch.setattr(
        speakable_page.page_validation,
        "OpenAiPageValidator",
        lambda: FakeValidator(ValidationVerdict(
            text_matches=True, age_suitable=True, certain=True,
        )),
    )

    response = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": profile_id,
        "image_base64": _image_base64(),
        "lines": [_line("Read this exact line")],
    })

    assert response.status_code == 200
    assert response.json()["status"] == "approved"
    assert response.headers["cache-control"] == "no-store"
    assert page_approval.verify_approval(
        response.json()["proof"], user_id, profile_id, ["Read this exact line"]
    )


def test_validate_blocks_uncertain_page_without_proof(client, db, monkeypatch):
    headers = _auth(client, "page-validation-blocked")
    user_id = _user(headers)
    profile_id = "page-validation-blocked-profile"
    _owned_profile(db, user_id, profile_id)
    monkeypatch.setattr(
        speakable_page.page_validation,
        "OpenAiPageValidator",
        lambda: FakeValidator(ValidationVerdict(
            text_matches=True, age_suitable=True, certain=False,
        )),
    )

    response = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": profile_id,
        "image_base64": _image_base64(),
        "lines": [_line()],
    })

    assert response.status_code == 200
    assert response.json() == {"status": "blocked", "reason": "content_unsuitable"}
    assert response.headers["cache-control"] == "no-store"


def test_audio_returns_complete_ordered_bundle_and_never_partial(
    client, db, monkeypatch
):
    headers = _auth(client, "page-audio-bundle")
    user_id = _user(headers)
    profile_id = "page-audio-profile"
    _owned_profile(db, user_id, profile_id)
    lines = ["First line", "Second line"]
    proof = page_approval.issue_approval(user_id, profile_id, lines)
    service = FakeTts()
    monkeypatch.setattr(speakable_page, "get_openai_tts_service", lambda: service)

    response = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": proof, "lines": lines,
    })

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"
    assert response.headers["cache-control"] == "no-store"
    assert service.calls == lines
    with ZipFile(BytesIO(response.content)) as bundle:
        assert bundle.namelist() == ["000.mp3", "001.mp3"]
        assert bundle.read("000.mp3") == b"MP3:First line"
        assert bundle.read("001.mp3") == b"MP3:Second line"

    failed = FakeTts(fail_on="Second line")
    monkeypatch.setattr(speakable_page, "get_openai_tts_service", lambda: failed)
    response = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": proof, "lines": lines,
    })
    assert response.status_code == 502
    assert b"First line" not in response.content
    assert b"Second line" not in response.content


def test_invalid_proof_makes_no_tts_calls_even_with_old_flags_disabled(
    client, db, monkeypatch
):
    headers = _auth(client, "page-audio-denied")
    user_id = _user(headers)
    profile_id = "page-audio-denied-profile"
    _owned_profile(db, user_id, profile_id)
    service = FakeTts()
    monkeypatch.setattr(speakable_page, "get_openai_tts_service", lambda: service)
    response = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": "invalid", "lines": ["private text"],
    })
    assert response.status_code == 403
    assert service.calls == []

    settings = db.get(PrivacySettings, user_id)
    settings.page_image_validation_enabled = False
    settings.cloud_tts_enabled = False
    db.flush()
    proof = page_approval.issue_approval(user_id, profile_id, ["private text"])
    response = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": proof, "lines": ["private text"],
    })
    assert response.status_code == 200
    assert service.calls == ["private text"]


def test_legacy_flags_off_still_validate_and_generate_audio(client, db, monkeypatch):
    headers = _auth(client, "page-legacy-flags")
    user_id = _user(headers)
    profile_id = "page-legacy-profile"
    _owned_profile(db, user_id, profile_id)
    settings = db.get(PrivacySettings, user_id)
    settings.cloud_tts_enabled = False
    settings.page_image_validation_enabled = False
    db.flush()
    monkeypatch.setattr(
        speakable_page.page_validation, "OpenAiPageValidator",
        lambda: FakeValidator(ValidationVerdict(
            text_matches=True, age_suitable=True, certain=True,
        )),
    )
    service = FakeTts()
    monkeypatch.setattr(speakable_page, "get_openai_tts_service", lambda: service)

    validation = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": profile_id, "image_base64": _image_base64(),
        "lines": [_line("A little fox")],
    })
    assert validation.status_code == 200
    assert validation.json()["status"] == "approved"
    audio = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": validation.json()["proof"],
        "lines": ["A little fox"],
    })
    assert audio.status_code == 200
    assert service.calls == ["A little fox"]


def test_invalid_request_does_not_echo_ocr_text(client):
    headers = _auth(client, "page-validation-invalid")
    private_line = "PRIVATE OCR " + "x" * 4100
    response = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": "profile",
        "image_base64": "invalid",
        "lines": [_line(private_line)],
    })
    assert response.status_code == 422
    assert private_line not in response.text


def test_explicit_language_normalized_proof_and_audio(client, db, monkeypatch):
    headers = _auth(client, "page-vietnamese")
    user_id = _user(headers)
    profile_id = "page-vietnamese-profile"
    _owned_profile(db, user_id, profile_id)
    seen = []
    class Validator:
        def validate(self, image, lines, age_band, content_language=None):
            seen.append((lines, content_language))
            return ValidationVerdict(text_matches=True, age_suitable=True, certain=True,
                                     text_certain=True, suitability_certain=True)
    monkeypatch.setattr(speakable_page.page_validation, "OpenAiPageValidator", Validator)
    service = FakeTts()
    monkeypatch.setattr(speakable_page, "get_openai_tts_service", lambda: service)
    validation = client.post("/v1/speakable-page/validate", headers=headers, json={
        "profile_id": profile_id, "image_base64": _image_base64(),
        "content_language": "vi", "lines": [_line("Tiếng Việt")],
    })
    assert seen == [(["Tiếng Việt"], "vi")]
    proof = validation.json()["proof"]
    body = {"profile_id": profile_id, "proof": proof, "content_language": "vi", "lines": ["Tiếng Việt"]}
    assert client.post("/v1/speakable-page/audio", headers=headers, json=body).status_code == 200
    assert service.calls == ["Tiếng Việt"]
    body["content_language"] = "en"
    response = client.post("/v1/speakable-page/audio", headers=headers, json=body)
    assert response.status_code == 403
    assert response.json()["detail"] == "page_approval_invalid"
    assert service.calls == ["Tiếng Việt"]
