import base64
import json
import logging
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


def narration_line(text, top=.1, language="vi"):
    return {"text": text, "left": .1, "top": top, "width": .6, "height": .04,
            "recognizedLanguage": language}


def test_narration_joins_vietnamese_wraps_including_commas_and_preserves_geometry():
    lines = [narration_line(text, top=.1 + index * .05) for index, text in enumerate([
        "18",
        "Cam ngồi một mình trên cành cây. Chẳng bao lâu sau, một",
        "bạn Vẹt xanh đáp xuống cạnh cậu ấy.",
        '*Có chuyện gì vậy Cam?" Ban Vẹt hỏi.',
        '“Tớ muốn chơi với ai đó giống như tớ." Cam đáp. "Nhưng',
        'chẳng có ai cả."',
        '“Dĩ nhiên là không có rồi." Vẹt nói. "Chúng ta đều khác',
        'nhau, và chúng ta đều đặc biệt"',
        "Cam bắt đầu nghĩ về", "những điều khiến", "cho cậu ấy trở", "nên đặc biệt...",
    ])]
    segments = page_ocr.narration_segments(lines)
    assert [segment["text"] for segment in segments] == [
        "18",
        "Cam ngồi một mình trên cành cây. Chẳng bao lâu sau, một bạn Vẹt xanh đáp xuống cạnh cậu ấy.",
        '*Có chuyện gì vậy Cam?" Ban Vẹt hỏi.',
        '“Tớ muốn chơi với ai đó giống như tớ." Cam đáp. "Nhưng chẳng có ai cả."',
        '“Dĩ nhiên là không có rồi." Vẹt nói. "Chúng ta đều khác nhau, và chúng ta đều đặc biệt" '
        "Cam bắt đầu nghĩ về những điều khiến cho cậu ấy trở nên đặc biệt...",
    ]
    assert segments[1]["top"] == pytest.approx(.15)
    assert segments[1]["height"] == pytest.approx(.09)
    assert segments[1]["recognizedLanguage"] == "vi"
    assert lines[1]["text"].endswith("một")  # Do not mutate source OCR lines.


@pytest.mark.parametrize("ending", [".", "?", "!", "…", "...", '."', '?”', "!’", ".)"])
def test_narration_keeps_sentence_endings_separate(ending):
    lines = [narration_line("Done" + ending), narration_line("Next")]
    assert page_ocr.narration_segments(lines) == lines


def test_narration_keeps_numbers_and_language_changes_separate():
    lines = [narration_line("Hello", language="en"), narration_line("Xin chào"),
             narration_line("18"), narration_line("Tiếp theo")]
    assert page_ocr.narration_segments(lines) == lines
    assert page_ocr.narration_segments([]) == []


def test_narration_limits_include_joining_spaces():
    with pytest.raises(ValueError, match="OCR page too long"):
        page_ocr.narration_segments([narration_line("a" * 2000), narration_line("b" * 2000)])


@pytest.mark.parametrize("top", [.02, .9643623872906827])
def test_page_number_filter_excludes_small_isolated_margin_numbers(top):
    number = {**narration_line("18", top=top, language="mixed"),
              "left": .040051679586563305, "width": .021533161068044794,
              "height": .012451696006869906}
    body = [narration_line("Cam bắt đầu nghĩ về", top=.42),
            narration_line("những điều khiến cậu ấy đặc biệt...", top=.57)]
    lines = [number, *body]  # Vision can return a footer before the story.
    kept, excluded = page_ocr.filter_page_numbers(lines)
    assert kept == body
    assert excluded == [number]
    assert lines == [number, *body]
    assert page_ocr.narration_segments(kept)[0]["text"].startswith("Cam")


@pytest.mark.parametrize("number,body", [
    (narration_line("18", top=.5), narration_line("Story", top=.3)),
    (narration_line("18", top=.95), narration_line("Story", top=.3)),
    ({**narration_line("18", top=.95), "height": .01}, narration_line("Story", top=.89)),
    ({**narration_line("18 apples", top=.95), "height": .01}, narration_line("Story", top=.3)),
    ({**narration_line("IV", top=.95), "height": .01}, narration_line("Story", top=.3)),
    ({**narration_line("18", top=.08), "height": .01}, narration_line("Story", top=.3)),
])
def test_page_number_filter_preserves_ambiguous_or_story_numbers(number, body):
    lines = [number, body]
    assert page_ocr.filter_page_numbers(lines) == (lines, [])


def test_page_number_filter_preserves_number_only_pages_and_empty_pages():
    lines = [{**narration_line("18", top=.95), "height": .01}]
    assert page_ocr.filter_page_numbers(lines) == (lines, [])
    assert page_ocr.filter_page_numbers([]) == ([], [])


def test_vision_filters_page_number_before_returning_narration(monkeypatch, caplog):
    monkeypatch.setattr(settings, "google_vision_api_key", "test-key")
    monkeypatch.setattr(settings, "scan_ocr_debug_logging", True)
    number = word("18", y=193, language="mixed")
    number["boundingBox"]["vertices"] = [{"x": 4, "y": 193}, {"x": 6, "y": 195}]
    document = annotation([number, word("Cam bắt đầu", y=20), word("nghĩ về.", y=40)])
    original = httpx.Client
    monkeypatch.setattr(page_ocr.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json={
            "responses": [{"fullTextAnnotation": document}],
        })), **kw))
    with caplog.at_level(logging.INFO, logger="uvicorn.error.scan"):
        segments = page_ocr.GoogleVisionOcr().recognize(b"jpeg", 100, 200)
    assert [segment["text"] for segment in segments] == ["Cam bắt đầu nghĩ về."]
    messages = [record.getMessage() for record in caplog.records]
    for prefix in ["scan_ocr_lines ", "scan_ocr_excluded_page_numbers "]:
        payload = next(message.removeprefix(prefix) for message in messages if message.startswith(prefix))
        assert json.loads(payload)[0]["text"] == "18"


def test_vision_returns_joined_narration_segments(monkeypatch):
    monkeypatch.setattr(settings, "google_vision_api_key", "test-key")
    document = annotation([word("Cam bắt đầu", y=20), word("nghĩ về.", y=40)])
    original = httpx.Client
    monkeypatch.setattr(page_ocr.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json={
            "responses": [{"fullTextAnnotation": document}],
        })), **kw))
    segments = page_ocr.GoogleVisionOcr().recognize(b"jpeg", 100, 200)
    assert len(segments) == 1
    assert segments[0]["text"] == "Cam bắt đầu nghĩ về."
    assert segments[0]["height"] == pytest.approx(.15)


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
    ("approved", "approved"), ("empty", "blocked"),
    ("failed", "temporary_error"),
])
def test_vision_route_uses_only_cloud_text_and_binds_approval(monkeypatch, outcome, expected):
    from starlette.requests import Request
    from app.routers import speakable_page
    from app.schemas import ValidatePageRequest
    from app.services import page_approval

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

    monkeypatch.setattr(speakable_page.page_ocr, "GoogleVisionOcr", Ocr)
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


@pytest.mark.parametrize("enabled,invalid_geometry", [(False, False), (True, False), (True, True)])
def test_debug_logs_ocr_before_parsing_without_image_or_key(monkeypatch, caplog, enabled, invalid_geometry):
    monkeypatch.setattr(settings, "google_vision_api_key", "private-api-key")
    monkeypatch.setattr(settings, "scan_ocr_debug_logging", enabled)
    document = annotation([word("Vẹt")])
    document["text"] = "Vẹt\nReading"
    if invalid_geometry:
        document["pages"][0]["width"] = 999
    original = httpx.Client
    monkeypatch.setattr(page_ocr.httpx, "Client", lambda **kw: original(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json={
            "responses": [{"fullTextAnnotation": document}],
        })), **kw))
    with caplog.at_level(logging.INFO, logger="uvicorn.error.scan"):
        if invalid_geometry:
            with pytest.raises(ValueError):
                page_ocr.GoogleVisionOcr().recognize(b"private-image", 100, 200)
        else:
            page_ocr.GoogleVisionOcr().recognize(b"private-image", 100, 200)
    messages = [record.getMessage() for record in caplog.records]
    raw = [message for message in messages if message.startswith("scan_ocr_raw ")]
    parsed = [message for message in messages if message.startswith("scan_ocr_lines ")]
    assert bool(raw) == enabled
    assert bool(parsed) == (enabled and not invalid_geometry)
    if enabled:
        assert json.loads(raw[0].removeprefix("scan_ocr_raw "))["text"] == "Vẹt\nReading"
        assert "\n" not in raw[0]
    else:
        assert "Vẹt" not in caplog.text
    assert "private-api-key" not in caplog.text
    assert "private-image" not in caplog.text
    assert base64.b64encode(b"private-image").decode() not in caplog.text
