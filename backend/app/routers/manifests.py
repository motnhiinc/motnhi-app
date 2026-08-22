from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import manifests as repo
from app.schemas import ImageTargetManifest

router = APIRouter(prefix="/v1/stories", tags=["manifests"])


@router.get("/{story_id}/image-target-manifest", response_model=ImageTargetManifest)
def image_target_manifest(
    story_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ImageTargetManifest:
    manifest = repo.build_image_target_manifest(db, user.id, story_id)
    if manifest is None:
        raise HTTPException(status_code=404, detail="story not found")
    return manifest
