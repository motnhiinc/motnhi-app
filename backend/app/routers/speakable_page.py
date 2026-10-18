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
from app.services import page_approval, page_validation, page_correction, page_audio, privacy as privacy_service
from app.services.tts import TtsUpstreamError, get_openai_tts_service, provider_reason

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
        image, _, _ = page_validation.decode_page_image(body.image_base64)
    except page_validation.PageValidationError as error:
        raise HTTPException(status_code=422, detail="invalid page") from error
    started = monotonic()
    outcome = "provider_failed"
    corrected_lines = None
    segment_languages = None
    try:
        lines = [unicodedata.normalize("NFC", line.text) if body.content_language else line.text for line in body.lines]
        if body.correct_ocr:
            verdict = page_correction.OpenRouterPageCorrector().validate(
                image, body.lines, profile.age_band, body.content_language)
            reason = verdict.blocked_reason
            if reason is None:
                corrected_lines = verdict.corrected_lines(body.lines)
                lines = [line["text"] for line in corrected_lines]
                segment_languages = [line["recognizedLanguage"] for line in corrected_lines]
        else:
            validator = page_validation.OpenAiPageValidator()
            verdict = (validator.validate(image, lines, profile.age_band) if body.content_language is None else
                       validator.validate(image, lines, profile.age_band, body.content_language))
            reason = verdict.blocked_reason
        outcome = reason or "approved"
    except Exception as error:
        outcome = provider_reason(error)
        return Response(
            content=json.dumps({"status": "temporary_error", "reason": provider_reason(error)}).encode(),
            status_code=503,
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
    finally:
        logging.getLogger("uvicorn.error.scan").info("scan_stage %s stage=validation_provider reason=%s elapsed_ms=%d", correlation(request), outcome, (monotonic() - started) * 1000)
    if reason is not None:
        return Response(
            content=json.dumps({"status": "blocked", "reason": reason}).encode(),
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
    proof = page_approval.issue_approval(user.id, body.profile_id, lines, body.content_language,
                                        segment_languages=segment_languages)
    payload = {"status": "approved", "proof": proof}
    if corrected_lines is not None:
        payload["corrected_lines"] = corrected_lines
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
        bundle = page_audio.generate_bundle(get_openai_tts_service(), body.lines, body.content_language,
                                            correlation=correlation(request), segment_languages=languages)
    except TtsUpstreamError as error:
        raise HTTPException(status_code=503, detail=error.reason) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail="provider_failed") from error
    return Response(bundle, media_type="application/zip", headers={"Cache-Control": "no-store"})
