import base64
from dataclasses import dataclass
from datetime import datetime, timezone
from io import BytesIO
from zipfile import ZipFile

from PIL import Image

from app.auth import decode_token
from app.models import ChildProfile, PrivacySettings
from app.routers import speakable_page
from app.services import page_approval
from app.services.page_validation import ValidationVerdict

POLICY = "2026-09-26"


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

    def validate(self, image, lines, age_band):
        assert image.startswith(b"\xff\xd8\xff")
        assert age_band == "5-6"
        return self.verdict


@dataclass
class FakeTts:
    fail_on: str | None = None
    calls: list[str] | None = None

    def __post_init__(self):
        self.calls = []

    def generate(self, text):
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
    assert response.json() == {"status": "blocked"}
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


def test_invalid_proof_and_disabled_image_consent_make_no_tts_calls(
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

    db.get(PrivacySettings, user_id).page_image_validation_enabled = False
    db.flush()
    proof = page_approval.issue_approval(user_id, profile_id, ["private text"])
    response = client.post("/v1/speakable-page/audio", headers=headers, json={
        "profile_id": profile_id, "proof": proof, "lines": ["private text"],
    })
    assert response.status_code == 403
    assert service.calls == []


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
