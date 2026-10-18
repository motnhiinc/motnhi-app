import json
import logging
from time import monotonic
import unicodedata
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, Request
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo, profiles
from app.schemas import PageAudioRequest, ValidatePageRequest
from app.services import page_approval, page_validation, page_ocr, page_audio, privacy as privacy_service
from app.services.tts import TtsUpstreamError, get_elevenlabs_tts_service, provider_reason

router = APIRouter(prefix="/v1/speakable-page", tags=["speakable-page"])


def correlation(request: Request) -> str:
    fields = []
    for header, name in [("X-Scan-Attempt-Id", "attempt"), ("X-Scan-Operation-Id", "operation")]:
        try:
            fields.append(f"{name}={UUID(request.headers.get(header, ''))}")
        except ValueError:
            pass
    return " ".join(fields)


@router.post("/validate")
def validate_page(
    body: ValidatePageRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        privacy_service.require_core_storage(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    profile = profiles.get_owned(db, user.id, body.profile_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")
    try:
        image, width, height = page_validation.decode_page_image(body.image_base64)
    except page_validation.PageValidationError as error:
        raise HTTPException(status_code=422, detail="invalid page") from error
    started = monotonic()
    outcome = "provider_failed"
    recognized_lines = None
    segment_languages = None
    stage = "page_checks"
    try:
        lines = [unicodedata.normalize("NFC", line.text) if body.content_language else line.text for line in body.lines]
        if body.ocr_provider == "google_vision":
            stage = "ocr_provider"
            recognized_lines = page_ocr.GoogleVisionOcr().recognize(image, width, height)
            logging.getLogger("uvicorn.error.scan").info(
                "scan_stage %s stage=ocr_provider reason=recognized line_count=%d elapsed_ms=%d",
                correlation(request), len(recognized_lines), (monotonic() - started) * 1000)
            stage = "page_checks"
            lines = [line["text"] for line in recognized_lines]
            segment_languages = [line["recognizedLanguage"] for line in recognized_lines]
        # OCR text is authoritative. No LLM correction, text-match validation,
        # or age-suitability provider call occurs before narration.
        reason = "recognition_uncertain" if not lines else None
        outcome = reason or "approved"
    except Exception as error:
        outcome = provider_reason(error)
        # Exception messages/tracebacks can contain source text or credentials.
        logging.getLogger("uvicorn.error.scan").warning(
            "scan_failure %s stage=%s reason=%s error_type=%s",
            correlation(request), stage, outcome, type(error).__name__)
        return Response(
            content=json.dumps({"status": "temporary_error", "reason": provider_reason(error)}).encode(),
            status_code=503,
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
    finally:
        logging.getLogger("uvicorn.error.scan").info("scan_stage %s stage=%s reason=%s elapsed_ms=%d", correlation(request), stage, outcome, (monotonic() - started) * 1000)
    if reason is not None:
        return Response(
            content=json.dumps({"status": "blocked", "reason": reason}).encode(),
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
    proof = page_approval.issue_approval(user.id, body.profile_id, lines, body.content_language,
                                        segment_languages=segment_languages)
    payload = {"status": "approved", "proof": proof}
    if recognized_lines is not None:
        payload["recognized_lines"] = recognized_lines
    return Response(
        content=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        media_type="application/json",
        headers={"Cache-Control": "no-store"},
    )


@router.post("/audio")
def generate_page_audio(
    body: PageAudioRequest,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        privacy_service.require_core_storage(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    if profiles.get_owned(db, user.id, body.profile_id) is None:
        raise HTTPException(status_code=404, detail="profile not found")
    reason = page_approval.approval_reason(body.proof, user.id, body.profile_id, body.lines, body.content_language)
    if reason:
        raise HTTPException(status_code=403, detail=reason)
    try:
        languages = page_approval.approved_segment_languages(body.proof, len(body.lines))
        bundle = page_audio.generate_bundle(get_elevenlabs_tts_service(), body.lines, body.content_language,
                                            correlation=correlation(request), segment_languages=languages)
    except TtsUpstreamError as error:
        raise HTTPException(status_code=503, detail=error.reason) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="provider_failed") from error
    return Response(bundle, media_type="application/zip", headers={"Cache-Control": "no-store"})
