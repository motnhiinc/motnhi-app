"""Cloud Vision document OCR. Text and geometry come only from Vision, not an LLM."""
import base64
import unicodedata

import httpx

from app.config import settings
from app.schemas import PageLine


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
            raise ValueError("Vision OCR failed")
        return document_lines(results[0].get("fullTextAnnotation", {}), width, height)


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
