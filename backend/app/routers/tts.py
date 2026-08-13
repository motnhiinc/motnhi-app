from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, StringConstraints

from app.auth import get_current_user
from app.models import User
from app.services.tts import OpenAiTtsService, TtsUpstreamError, get_openai_tts_service

router = APIRouter(prefix="/v1/tts", tags=["tts"])
ConfirmedText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)
]


class TtsRequest(BaseModel):
    text: ConfirmedText


def get_tts_service() -> OpenAiTtsService:
    return get_openai_tts_service()


@router.post("")
def generate_tts(
    request: TtsRequest,
    _: User = Depends(get_current_user),
    service: OpenAiTtsService = Depends(get_tts_service),
) -> Response:
    try:
        audio = service.generate(request.text)
    except TtsUpstreamError as error:
        raise HTTPException(status_code=502, detail="narration generation failed") from error
    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={"Cache-Control": "no-store"},
    )
