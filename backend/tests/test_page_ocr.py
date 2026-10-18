import base64
import json
from types import SimpleNamespace

import httpx
import pytest

from app.config import settings
from app.services import page_ocr


def word(text, x=10, y=20, language="vi", ending="LINE_BREAK"):
    symbols = [{"text": c} for c in text]
    symbols[-1]["property"] = {"detectedBreak": {"type": ending}}
    return {
        "boundingBox": {"vertices": [{"x": x, "y": y}, {"x": x+60, "y": y+10}]},
        "property": {"detectedLanguages": [{"languageCode": language}]},
        "symbols": symbols,
    }


def annotation(words):
    return {"pages": [{"width": 100, "height": 200, "blocks": [
        {"paragraphs": [{"words": words}]},
    ]}]}


def test_text_normalization_line_breaks_languages_and_geometry():
    lines = page_ocr.document_lines(annotation([
        word("Vẹt"), word("Reading", y=40, language="en"),
    ]), 100, 200)
    assert [line["text"] for line in lines] == ["Vẹt", "Reading"]
    assert [line["recognizedLanguage"] for line in lines] == ["vi", "en"]
    assert lines[0]["left"] == .1
    assert lines[0]["top"] == .1
    assert lines[0]["width"] == pytest.approx(.6)
    assert lines[0]["height"] == pytest.approx(.05)


def test_spaces_mixed_language_and_paragraph_flush():
    lines = page_ocr.document_lines(annotation([
        word("Bạn", ending="SPACE"), word("Reading", language="en", ending=None),
    ]), 100, 200)
    assert lines[0]["text"] == "Bạn Reading"
    assert lines[0]["recognizedLanguage"] == "mixed"


def test_empty_page_is_not_fabricated():
    assert page_ocr.document_lines({}, 100, 200) == []


def test_invalid_dimensions_and_page_limits():
    with pytest.raises(ValueError):
        page_ocr.document_lines(annotation([word("Vẹt")]), 200, 100)
    with pytest.raises(ValueError):
        page_ocr.document_lines(annotation([word("Vẹt")]*41), 100, 200)
    with pytest.raises(ValueError):
        page_ocr.document_lines(annotation([word("a"*4001)]), 100, 200)


@pytest.mark.parametrize("payload,fails", [
    ({"responses": [{"fullTextAnnotation": annotation([word("Vẹt")])}]}, False),
    ({"responses": [{"error": {"code": 8, "message": "secret"}}]}, True),
    ({"responses": []}, True),
])
def test_rest_request_and_provider_errors(monkeypatch, payload, fails):
    monkeypatch.setattr(settings, "google_vision_api_key", "test-key")

    def handle(request):
        body = json.loads(request.content)
        assert request.headers["X-Goog-Api-Key"] == "test-key"
        assert "key=" not in str(request.url)
        assert body["requests"][0]["features"] == [{"type": "DOCUMENT_TEXT_DETECTION"}]
        assert body["requests"][0]["image"]["content"] == base64.b64encode(b"jpeg").decode()
        return httpx.Response(200, json=payload)

    original = httpx.Client
    monkeypatch.setattr(page_ocr.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(handle), **kw))
    if fails:
        with pytest.raises(ValueError):
            page_ocr.GoogleVisionOcr().recognize(b"jpeg", 100, 200)
    else:
        assert page_ocr.GoogleVisionOcr().recognize(b"jpeg", 100, 200)[0]["text"] == "Vẹt"


def test_missing_key_fails_before_upload(monkeypatch):
    monkeypatch.setattr(settings, "google_vision_api_key", "")
    with pytest.raises(RuntimeError):
        page_ocr.GoogleVisionOcr().recognize(b"jpeg", 100, 200)


@pytest.mark.parametrize("outcome,expected", [
    ("approved", "approved"), ("blocked", "blocked"), ("empty", "blocked"),
    ("failed", "temporary_error"),
])
def test_vision_route_uses_only_cloud_text_and_binds_approval(monkeypatch, outcome, expected):
    from starlette.requests import Request
    from app.routers import speakable_page
    from app.schemas import ValidatePageRequest
    from app.services import page_approval
    from app.services.page_validation import ValidationVerdict

    recognized = [{**{"text": "Vẹt", "left": .1, "top": .1, "width": .6, "height": .1},
                   "recognizedLanguage": "vi"}]
    monkeypatch.setattr(speakable_page.privacy_repo, "get_settings", lambda *args: None)
    monkeypatch.setattr(speakable_page.privacy_service, "require_core_storage", lambda *args: None)
    monkeypatch.setattr(speakable_page.profiles, "get_owned", lambda *args: SimpleNamespace(age_band="5-6"))
    monkeypatch.setattr(speakable_page.page_validation, "decode_page_image", lambda *args: (b"jpeg", 100, 200))

    class Ocr:
        def recognize(self, image, width, height):
            assert (image, width, height) == (b"jpeg", 100, 200)
            if outcome == "failed":
                raise ValueError("private provider error")
            return [] if outcome == "empty" else recognized

    class Validator:
        def validate(self, image, lines, age, language):
            assert lines == ["Vẹt"]
            return ValidationVerdict(text_matches=True, age_suitable=outcome != "blocked", certain=True)

    monkeypatch.setattr(speakable_page.page_ocr, "GoogleVisionOcr", Ocr)
    monkeypatch.setattr(speakable_page.page_validation, "OpenAiPageValidator", Validator)
    body = ValidatePageRequest(profile_id="profile", image_base64="jpeg",
                               content_language="vi", ocr_provider="google_vision")
    response = speakable_page.validate_page(body, Request({"type": "http", "headers": []}),
                                            db=None, user=SimpleNamespace(id="user"))
    payload = json.loads(response.body)
    assert payload["status"] == expected
    if expected == "approved":
        assert payload["recognized_lines"] == recognized
        assert page_approval.verify_approval(payload["proof"], "user", "profile", ["Vẹt"], "vi")
        assert not page_approval.verify_approval(payload["proof"], "user", "profile", ["Vét"], "vi")
        assert page_approval.approved_segment_languages(payload["proof"], 1) == ["vi"]
    else:
        assert "proof" not in payload and "recognized_lines" not in payload


def test_removed_correction_protocol_is_rejected():
    from app.schemas import ValidatePageRequest
    with pytest.raises(ValueError):
        ValidatePageRequest(profile_id="profile", image_base64="jpeg", correct_ocr=True)
