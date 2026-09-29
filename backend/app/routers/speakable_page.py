from io import BytesIO
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

router = APIRouter(prefix="/v1/speakable-page", tags=["speakable-page"])


@router.post("/validate")
def validate_page(
    body: ValidatePageRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    try:
        privacy_service.require_page_reading(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    profile = profiles.get_owned(db, user.id, body.profile_id)
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")
    try:
        image, _, _ = page_validation.decode_page_image(body.image_base64)
    except page_validation.PageValidationError as error:
        raise HTTPException(status_code=422, detail="invalid page") from error
    try:
        validator = page_validation.OpenAiPageValidator()
        verdict = validator.validate(image, [line.text for line in body.lines], profile.age_band)
        approved = (
            verdict.text_matches is True
            and verdict.age_suitable is True
            and verdict.certain is True
        )
    except Exception:
        return Response(
            content=b'{"status":"temporary_error"}',
            status_code=503,
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
    if not approved:
        return Response(
            content=b'{"status":"blocked"}',
            media_type="application/json",
            headers={"Cache-Control": "no-store"},
        )
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
        privacy_service.require_page_reading(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    if profiles.get_owned(db, user.id, body.profile_id) is None:
        raise HTTPException(status_code=404, detail="profile not found")
    if not page_approval.verify_approval(body.proof, user.id, body.profile_id, body.lines):
        raise HTTPException(status_code=403, detail="page_approval_invalid")
    try:
        service: OpenAiTtsService = get_openai_tts_service()
        buffer = BytesIO()
        with ZipFile(buffer, "w", compression=ZIP_STORED) as archive:
            for index, text in enumerate(body.lines):
                audio = service.generate(text)
                if not audio or len(audio) > 2 * 1024 * 1024:
                    raise TtsUpstreamError("invalid audio")
                archive.writestr(f"{index:03d}.mp3", audio)
                if buffer.tell() > 32 * 1024 * 1024:
                    raise TtsUpstreamError("bundle too large")
    except Exception as error:
        raise HTTPException(status_code=502, detail="narration generation failed") from error
    return Response(buffer.getvalue(), media_type="application/zip", headers={"Cache-Control": "no-store"})
