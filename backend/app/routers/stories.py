from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import stories as repo
from app.schemas import LibraryResponse, StoryDetailResponse

router = APIRouter(prefix="/v1/stories", tags=["stories"])


@router.get("", response_model=LibraryResponse)
def library(
    age_band: str | None = None,
    language: str | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LibraryResponse:
    return LibraryResponse(stories=repo.list_published(db, user.id, age_band, language))


@router.get("/{story_id}", response_model=StoryDetailResponse)
def detail(
    story_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> StoryDetailResponse:
    payload = repo.get_detail(db, user.id, story_id)
    if payload is None:
        raise HTTPException(status_code=404, detail="story not found")
    return payload
