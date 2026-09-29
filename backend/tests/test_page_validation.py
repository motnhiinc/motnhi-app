import base64
from io import BytesIO

import pytest
from PIL import Image

from app.services import page_approval, page_validation


def _jpeg(width=80, height=120):
    output = BytesIO()
    Image.new("RGB", (width, height), "white").save(output, format="JPEG")
    return output.getvalue()


def test_jpeg_decoder_accepts_bounded_image_and_reports_dimensions():
    raw = _jpeg()
    image, width, height = page_validation.decode_page_image(base64.b64encode(raw).decode())
    assert image == raw
    assert (width, height) == (80, 120)


@pytest.mark.parametrize("encoded", ["not-base64", base64.b64encode(b"not jpeg").decode()])
def test_jpeg_decoder_rejects_invalid_payload(encoded):
    with pytest.raises(page_validation.PageValidationError):
        page_validation.decode_page_image(encoded)


def test_page_approval_is_bound_to_user_profile_and_exact_ordered_lines():
    lines = ["Exact text", "Dòng tiếng Việt"]
    proof = page_approval.issue_approval("user-a", "profile-a", lines)
    assert page_approval.verify_approval(proof, "user-a", "profile-a", lines)
    assert not page_approval.verify_approval(proof, "user-b", "profile-a", lines)
    assert not page_approval.verify_approval(proof, "user-a", "profile-b", lines)
    assert not page_approval.verify_approval(proof, "user-a", "profile-a", list(reversed(lines)))
