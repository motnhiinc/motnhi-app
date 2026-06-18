from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import profiles as repo
from app.schemas import ChildProfileIn, ChildProfileOut

router = APIRouter(prefix="/v1/child-profiles", tags=["child-profiles"])


@router.get("", response_model=list[ChildProfileOut])
def list_profiles(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return repo.list_for_user(db, user.id)


@router.post("", response_model=ChildProfileOut)
def create_profile(body: ChildProfileIn, db: Session = Depends(get_db),
                   user: User = Depends(get_current_user)):
    return repo.upsert(db, user.id, body.model_dump())


@router.patch("/{profile_id}", response_model=ChildProfileOut)
def patch_profile(profile_id: str, body: dict, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    existing = repo.get_owned(db, user.id, profile_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="profile not found")
    merged = {
        "id": profile_id,
        "nickname": body.get("nickname", existing.nickname),
        "age_band": body.get("age_band", existing.age_band),
        "language_code": body.get("language_code", existing.language_code),
        "bedtime_mode_default": body.get("bedtime_mode_default", existing.bedtime_mode_default),
        "microphone_enabled": body.get("microphone_enabled", existing.microphone_enabled),
        "ar_enabled": body.get("ar_enabled", existing.ar_enabled),
    }
    return repo.upsert(db, user.id, merged)
