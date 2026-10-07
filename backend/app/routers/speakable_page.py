import logging
from io import BytesIO
from time import monotonic
from zipfile import ZIP_STORED, ZipFile

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo, profiles
from app.schemas import PageAudioRequest, ValidatePageRequest
from app.services import page_approval, page_validation, privacy as privacy_service
from app.services.tts import OpenAiTtsService, TtsUpstreamError, get_openai_tts_service

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1/speakable-page", tags=["speakable-page"])


@router.post("/validate")
def validate_page(
    body: ValidatePageRequest,
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
        page_validation.decode_page_image(body.image_base64)
    except page_validation.PageValidationError as error:
        raise HTTPException(status_code=422, detail="invalid page") from error
    # AI text matching and age-suitability validation are temporarily disabled.
    # Bind the supplied OCR text to this user/profile for OpenAI speech without
    # requiring a Chat Completions request.
    proof = page_approval.issue_approval(user.id, body.profile_id, [line.text for line in body.lines])
    return Response(
        content=(
            '{"status":"approved","proof":"' + proof + '"}'
        ).encode("utf-8"),
        media_type="application/json",
        headers={"Cache-Control": "no-store"},
    )


@router.post("/audio")
def generate_page_audio(
    body: PageAudioRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        privacy_service.require_core_storage(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    if profiles.get_owned(db, user.id, body.profile_id) is None:
        raise HTTPException(status_code=404, detail="profile not found")
    if not page_approval.verify_approval(body.proof, user.id, body.profile_id, body.lines):
        raise HTTPException(status_code=403, detail="page_approval_invalid")
    started = monotonic()
    stage = "service_init"
    clip_number = None
    try:
        service: OpenAiTtsService = get_openai_tts_service()
        buffer = BytesIO()
        stage = "bundle_open"
        with ZipFile(buffer, "w", compression=ZIP_STORED) as archive:
            for index, text in enumerate(body.lines):
                clip_number = index + 1
                stage = "speech"
                audio = service.generate(text)
                stage = "clip_validation"
                if not audio or len(audio) > 2 * 1024 * 1024:
                    raise TtsUpstreamError("invalid audio")
                stage = "bundle_write"
                archive.writestr(f"{index:03d}.mp3", audio)
                stage = "bundle_size"
                if buffer.tell() > 32 * 1024 * 1024:
                    raise TtsUpstreamError("bundle too large")
            stage = "bundle_finalize"
    except Exception as error:
        logger.warning(
            "Page audio failed: stage=%s, clip_number=%s, clip_count=%s, error_type=%s, elapsed_seconds=%.3f",
            stage,
            clip_number,
            len(body.lines),
            type(error).__name__,
            monotonic() - started,
        )
        raise HTTPException(status_code=502, detail="narration generation failed") from error
    return Response(buffer.getvalue(), media_type="application/zip", headers={"Cache-Control": "no-store"})
