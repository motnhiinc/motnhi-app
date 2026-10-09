import logging
from io import BytesIO
from time import monotonic
from uuid import UUID, uuid4
from zipfile import ZIP_STORED, ZipFile

from fastapi import APIRouter, Depends, Header, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo, profiles
from app.schemas import PageAudioRequest, ValidatePageRequest
from app.services import page_approval, page_validation, privacy as privacy_service
from app.services.elevenlabs_tts import ElevenLabsTtsService, get_elevenlabs_tts_service
from app.services.page_narration import normalize_page_narration
from app.services.tts import TtsUpstreamError

logger = logging.getLogger(f"uvicorn.error.{__name__}")
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
    # Bind the supplied OCR text to this user/profile for cloud speech without
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
    x_request_id: str | None = Header(default=None),
):
    started = monotonic()
    try:
        request_id = str(UUID(x_request_id)) if x_request_id and len(x_request_id) <= 36 else str(uuid4())
    except ValueError:
        request_id = str(uuid4())
    try:
        privacy_service.require_core_storage(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    if profiles.get_owned(db, user.id, body.profile_id) is None:
        raise HTTPException(status_code=404, detail="profile not found")
    if not page_approval.verify_approval(body.proof, user.id, body.profile_id, body.lines):
        raise HTTPException(status_code=403, detail="page_approval_invalid")
    stage = "service_init"
    clip_number = None
    tts_seconds = 0.0
    logger.info("Page audio started: request_id=%s, clip_count=%s", request_id, len(body.lines))
    try:
        init_started = monotonic()
        service: ElevenLabsTtsService = get_elevenlabs_tts_service()
        init_seconds = monotonic() - init_started
        buffer = BytesIO()
        stage = "bundle_open"
        with ZipFile(buffer, "w", compression=ZIP_STORED) as archive:
            for index, text in enumerate(normalize_page_narration(body.lines)):
                clip_number = index + 1
                stage = "speech"
                clip_started = monotonic()
                try:
                    audio = service.generate(text, request_id=request_id, clip_number=clip_number)
                finally:
                    tts_seconds += monotonic() - clip_started
                logger.info(
                    "Page audio clip completed: request_id=%s, clip_number=%s, clip_count=%s, "
                    "chars=%s, audio_bytes=%s, elapsed_seconds=%.3f",
                    request_id, clip_number, len(body.lines), len(text), len(audio), monotonic() - clip_started,
                )
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
            "Page audio failed: stage=%s, clip_number=%s, clip_count=%s, error_type=%s, elapsed_seconds=%.3f, "
            "request_id=%s, tts_seconds=%.3f",
            stage,
            clip_number,
            len(body.lines),
            type(error).__name__,
            monotonic() - started,
            request_id,
            tts_seconds,
        )
        raise HTTPException(
            status_code=502, detail="narration generation failed", headers={"X-Request-ID": request_id},
        ) from error
    bundle = buffer.getvalue()
    elapsed = monotonic() - started
    logger.info(
        "Page audio completed: request_id=%s, clip_count=%s, bundle_bytes=%s, "
        "init_seconds=%.3f, tts_seconds=%.3f, other_seconds=%.3f, elapsed_seconds=%.3f",
        request_id, len(body.lines), len(bundle), init_seconds, tts_seconds,
        elapsed - tts_seconds - init_seconds, elapsed,
    )
    return Response(
        bundle, media_type="application/zip",
        headers={"Cache-Control": "no-store", "X-Request-ID": request_id},
    )
