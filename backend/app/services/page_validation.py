import base64
import binascii
import warnings
from io import BytesIO

from PIL import Image, UnidentifiedImageError

MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_IMAGE_EDGE = 3000


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
