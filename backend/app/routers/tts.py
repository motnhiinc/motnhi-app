from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, StringConstraints
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo
from app.services import privacy as privacy_service
from app.services.tts import OpenAiTtsService, TtsUpstreamError, get_openai_tts_service

router = APIRouter(prefix="/v1/tts", tags=["tts"])
ConfirmedText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)
]


class TtsRequest(BaseModel):
    text: ConfirmedText


def get_tts_service() -> OpenAiTtsService:
    try:
        return get_openai_tts_service()
    except TtsUpstreamError as error:
        raise HTTPException(status_code=502, detail="narration generation failed") from error


@router.post("")
def generate_tts(
    request: TtsRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    try:
        privacy_service.require_core_storage(privacy_repo.get_settings(db, user.id))
    except privacy_service.PrivacyError as error:
        raise HTTPException(status_code=error.status_code, detail=error.code) from error
    service = get_tts_service()
    try:
        audio = service.generate(request.text)
    except TtsUpstreamError as error:
        raise HTTPException(status_code=502, detail="narration generation failed") from error
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store"},
    )
