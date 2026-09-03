from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo
from app.repositories import stories as repo
from app.schemas import (
    CreateStoryRequest,
    LibraryResponse,
    StoryDetailResponse,
    StoryOut,
)
from app.services import privacy as privacy_service
from app.services.privacy import PrivacyError

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


@router.post("", response_model=StoryOut, status_code=201)
def create(
    body: CreateStoryRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> StoryOut:
    try:
        privacy_service.lock_user(db, user.id)
        settings = privacy_repo.get_settings(db, user.id)
        privacy_service.require_core_storage(settings)
        if repo.count_authored(db, user.id) >= repo.MAX_AUTHORED_PER_USER:
            raise HTTPException(status_code=409, detail="authored story limit reached")
        story = repo.create_authored(db, user.id, body)
        db.commit()
        return story
    except PrivacyError as exc:
        db.rollback()
        raise HTTPException(status_code=exc.status_code, detail=exc.code) from exc
    except Exception:
        db.rollback()
        raise


@router.delete("/{story_id}", status_code=204)
def delete(
    story_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    if not repo.delete_authored(db, user.id, story_id):
        raise HTTPException(status_code=404, detail="story not found")
    try:
        db.commit()
        return Response(status_code=204)
    except Exception:
        db.rollback()
        raise
