"""Cloud Vision document OCR. Text and geometry come only from Vision, not an LLM."""
import base64
import json
import logging
import unicodedata

import httpx

from app.config import settings
from app.schemas import PageLine

logger = logging.getLogger("uvicorn.error.scan")


class GoogleVisionOcr:
    def recognize(self, image: bytes, width: int, height: int) -> list[dict]:
        if not settings.google_vision_api_key:
            raise RuntimeError("Google Vision OCR unavailable")
        with httpx.Client(timeout=settings.google_vision_timeout_seconds) as client:
            response = client.post(
                "https://vision.googleapis.com/v1/images:annotate",
                headers={"X-Goog-Api-Key": settings.google_vision_api_key},
                json={"requests": [{
                    "image": {"content": base64.b64encode(image).decode("ascii")},
                    "features": [{"type": "DOCUMENT_TEXT_DETECTION"}],
                }]},
            )
            response.raise_for_status()
            results = response.json()["responses"]
        if len(results) != 1 or "error" in results[0]:
            code = results[0].get("error", {}).get("code") if len(results) == 1 else None
            logger.warning("scan_ocr provider=google_vision outcome=provider_error code=%s", code if isinstance(code, int) else "unknown")
            raise ValueError("Vision OCR failed")
        annotation = results[0].get("fullTextAnnotation", {})
        if settings.scan_ocr_debug_logging:
            # Log before parsing: geometry/limit failures must not hide the OCR.
            # JSON escapes newlines/control characters to keep one log record.
            text = annotation.get("text", "")
            logger.info("scan_ocr_raw %s", json.dumps({
                "provider": "google_vision", "image_width": width, "image_height": height,
                "pages": [{"width": p.get("width"), "height": p.get("height")}
                          for p in annotation.get("pages", [])],
                "text": text[:16000], "truncated": len(text) > 16000,
            }, ensure_ascii=False))
        lines = document_lines(annotation, width, height)
        if settings.scan_ocr_debug_logging:
            logger.info("scan_ocr_lines %s", json.dumps(lines, ensure_ascii=False))
        return lines


def document_lines(annotation: dict, width: int, height: int) -> list[dict]:
    # Keep Vision's page/block/paragraph reading order and detected line breaks.
    lines = []
    for page in annotation.get("pages", []):
        if page.get("width") != width or page.get("height") != height:
            raise ValueError("Vision image dimensions differ")
        for block in page.get("blocks", []):
            for paragraph in block.get("paragraphs", []):
                symbols = []
                vertices = []
                languages = set()

                def flush():
                    text = unicodedata.normalize("NFC", "".join(symbols).strip())
                    if not text:
                        return
                    if not vertices:
                        raise ValueError("missing OCR geometry")
                    xs = [max(0, min(width, v.get("x", 0))) / width for v in vertices]
                    ys = [max(0, min(height, v.get("y", 0))) / height for v in vertices]
                    line = PageLine(text=text, left=min(xs), top=min(ys),
                                    width=max(xs)-min(xs), height=max(ys)-min(ys))
                    language = next(iter(languages)) if len(languages) == 1 else "mixed"
                    if language not in {"vi", "en"}:
                        language = "mixed"
                    lines.append({**line.model_dump(), "recognizedLanguage": language})
                    symbols.clear()
                    vertices.clear()
                    languages.clear()

                for word in paragraph.get("words", []):
                    vertices.extend(word.get("boundingBox", {}).get("vertices", []))
                    for language in word.get("property", {}).get("detectedLanguages", []):
                        languages.add(language.get("languageCode", "mixed"))
                    for symbol in word.get("symbols", []):
                        symbols.append(symbol["text"])
                        kind = symbol.get("property", {}).get("detectedBreak", {}).get("type")
                        if kind in {"SPACE", "SURE_SPACE"}:
                            symbols.append(" ")
                        elif kind in {"EOL_SURE_SPACE", "LINE_BREAK", "HYPHEN"}:
                            if kind == "HYPHEN":
                                symbols.append("-")
                            flush()
                flush()
    if len(lines) > 40 or sum(len(line["text"]) for line in lines) > 4000:
        raise ValueError("OCR page too long")
    return lines
