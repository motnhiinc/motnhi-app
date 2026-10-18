import json
from types import SimpleNamespace

import pytest

from app.config import settings
from app.schemas import PageLine
from app.services import page_approval, page_correction


def verdict(indices=None, **overrides):
    return page_correction.CorrectionVerdict.model_validate({
        "readable": True, "age_suitable": True, "suitability_certain": True,
        "segments": [{"text": "Bạn Vẹt xanh đáp xuống cạnh cậu ấy.",
                      "source_lines": [0, 1] if indices is None else indices, "language": "vi"}],
        **overrides,
    })


def sources():
    return [PageLine(text="Bạn Vét xanh đáp", left=.1, top=.1, width=.8, height=.1),
            PageLine(text="xuống cạnh cậu ấy.", left=.1, top=.25, width=.5, height=.1)]


def test_correction_joins_wrapped_text_and_preserves_image_geometry():
    lines = verdict().corrected_lines(sources())
    assert len(lines) == 1
    assert lines[0]["text"] == "Bạn Vẹt xanh đáp xuống cạnh cậu ấy."
    assert lines[0]["source_lines"] == [0, 1]
    assert lines[0]["height"] == pytest.approx(.25)
    assert lines[0]["recognizedLanguage"] == "vi"


@pytest.mark.parametrize("indices", [[0], [1, 0], [-1, 0], [0, 0, 1], [0, 2]])
def test_correction_rejects_missing_reordered_or_fabricated_regions(indices):
    with pytest.raises(ValueError, match="mapping"):
        verdict(indices).corrected_lines(sources())


def test_unreadable_and_unsuitable_pages_cannot_be_approved():
    assert verdict(readable=False).blocked_reason == "recognition_uncertain"
    assert verdict(segments=[]).blocked_reason == "recognition_uncertain"
    assert verdict(suitability_certain=False).blocked_reason == "content_unsuitable"
    assert verdict(age_suitable=False).blocked_reason == "content_unsuitable"


def test_approval_binds_corrected_text_and_signed_segment_languages():
    text = ["Vẹt", "University of Reading"]
    proof = page_approval.issue_approval("user", "profile", text, "vi", segment_languages=["vi", "en"])
    assert page_approval.verify_approval(proof, "user", "profile", text, "vi")
    assert not page_approval.verify_approval(proof, "user", "profile", ["Vét", text[1]], "vi")
    assert page_approval.approved_segment_languages(proof, 2) == ["vi", "en"]


def test_openrouter_uses_separate_key_image_and_structured_response(monkeypatch):
    captured = {}

    class Client:
        def __init__(self, **kwargs):
            captured["client"] = kwargs
            self.chat = SimpleNamespace(completions=SimpleNamespace(create=self.create))

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def create(self, **kwargs):
            captured["request"] = kwargs
            return SimpleNamespace(choices=[SimpleNamespace(
                finish_reason="stop", message=SimpleNamespace(content=verdict().model_dump_json()))])

    monkeypatch.setattr(settings, "openrouter_api_key", "test-openrouter-key")
    monkeypatch.setattr(settings, "openai_api_key", "test-speech-key")
    monkeypatch.setattr(page_correction, "OpenAI", Client)
    result = page_correction.OpenRouterPageCorrector().validate(b"jpeg", sources(), "5-6", "vi")
    assert result.blocked_reason is None
    assert captured["client"]["api_key"] == "test-openrouter-key"
    assert captured["client"]["base_url"] == "https://openrouter.ai/api/v1"
    request = captured["request"]
    assert request["model"] == "google/gemini-2.5-flash"
    assert request["response_format"]["json_schema"]["strict"] is True
    content = request["messages"][1]["content"]
    assert json.loads(content[0]["text"])["ocr_lines"][0]["text"] == "Bạn Vét xanh đáp"
    assert content[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")


def test_missing_openrouter_key_does_not_fall_back_to_speech_key(monkeypatch):
    monkeypatch.setattr(settings, "openrouter_api_key", "")
    monkeypatch.setattr(settings, "openai_api_key", "speech-only")
    with pytest.raises(RuntimeError, match="unavailable"):
        page_correction.OpenRouterPageCorrector()
