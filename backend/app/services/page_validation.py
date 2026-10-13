import base64
import binascii
import json
import warnings
from io import BytesIO

from openai import OpenAI
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict

from app.config import settings

MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_IMAGE_EDGE = 3000


class ValidationVerdict(BaseModel):
    model_config = ConfigDict(extra="forbid")
    text_matches: bool
    age_suitable: bool
    certain: bool
    text_certain: bool | None = None
    suitability_certain: bool | None = None

    @property
    def blocked_reason(self) -> str | None:
        if not self.certain and self.text_certain is True and self.suitability_certain is True:
            return "content_unsuitable"
        if not self.age_suitable or not (self.suitability_certain if self.suitability_certain is not None else self.certain):
            return "content_unsuitable"
        if not (self.text_certain if self.text_certain is not None else self.certain):
            return "recognition_uncertain"
        return None if self.text_matches else "text_mismatch"


class PageValidationError(Exception):
    pass


def decode_page_image(image_base64: str) -> tuple[bytes, int, int]:
    if len(image_base64) > ((MAX_IMAGE_BYTES + 2) // 3) * 4:
        raise PageValidationError("invalid image")
    try:
        payload = base64.b64decode(image_base64, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise PageValidationError("invalid image") from exc
    if not payload or len(payload) > MAX_IMAGE_BYTES or not payload.startswith(b"\xff\xd8\xff"):
        raise PageValidationError("invalid image")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            image = Image.open(BytesIO(payload))
            if image.format != "JPEG":
                raise PageValidationError("invalid image")
            width, height = image.size
            if width < 1 or height < 1 or max(width, height) > MAX_IMAGE_EDGE:
                raise PageValidationError("invalid image")
            image.verify()
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise PageValidationError("invalid image") from exc
    return payload, width, height


class OpenAiPageValidator:
    def __init__(self) -> None:
        if not settings.openai_api_key:
            raise RuntimeError("validation unavailable")
        self.client = OpenAI(
            api_key=settings.openai_api_key,
            timeout=settings.openai_page_validation_timeout_seconds,
            max_retries=0,
        )

    def validate(self, image: bytes, lines: list[str], age_band: str, content_language: str | None = None) -> ValidationVerdict:
        response = self.client.chat.completions.create(
            model=settings.openai_page_validation_model,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": (
                        "Determine whether the OCR lines exactly match the visible page text, "
                        "whether the page is suitable for a child in age band " + age_band +
                        ", and independently whether text matching and suitability are certain. "
                        "Return only the required booleans. Selected dominant content language: " + (content_language or "unspecified") + ". "
                        "Do not rewrite text. OCR lines: " + json.dumps(lines, ensure_ascii=False)
                    )},
                    {"type": "image_url", "image_url": {
                        "url": "data:image/jpeg;base64," + base64.b64encode(image).decode("ascii")
                    }},
                ],
            }],
            response_format={"type": "json_schema", "json_schema": {
                "name": "page_validation",
                "strict": True,
                "schema": {
                    "type": "object",
                    "properties": {
                        "text_matches": {"type": "boolean"},
                        "age_suitable": {"type": "boolean"},
                        "certain": {"type": "boolean"},
                        "text_certain": {"type": "boolean"},
                        "suitability_certain": {"type": "boolean"},
                    },
                    "required": ["text_matches", "age_suitable", "certain", "text_certain", "suitability_certain"],
                    "additionalProperties": False,
                },
            }},
        )
        content = response.choices[0].message.content
        if not content:
            raise ValueError("empty verdict")
        return ValidationVerdict.model_validate_json(content)
