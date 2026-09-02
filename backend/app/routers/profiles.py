from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo
from app.repositories import profiles as repo
from app.schemas import ChildProfileIn, ChildProfileOut, ChildProfilePatch
from app.services import privacy as privacy_service
from app.services.privacy import PrivacyError

router = APIRouter(prefix="/v1/child-profiles", tags=["child-profiles"])


@router.get("", response_model=list[ChildProfileOut])
def list_profiles(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return repo.list_for_user(db, user.id)


@router.post("", response_model=ChildProfileOut)
def create_profile(body: ChildProfileIn, db: Session = Depends(get_db),
                   user: User = Depends(get_current_user)):
    try:
        privacy_service.lock_user(db, user.id)
        settings = privacy_repo.get_settings(db, user.id)
        privacy_service.require_core_storage(settings)
        result = repo.upsert(db, user.id, body.model_dump())
        db.commit()
        return result
    except PrivacyError as exc:
        db.rollback()
        raise HTTPException(status_code=exc.status_code, detail=exc.code) from exc
    except Exception:
        db.rollback()
        raise


@router.patch("/{profile_id}", response_model=ChildProfileOut)
def patch_profile(profile_id: str, body: ChildProfilePatch, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    existing = repo.get_owned(db, user.id, profile_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="profile not found")
    merged = {
        "id": profile_id,
        "nickname": body.nickname if body.nickname is not None else existing.nickname,
        "age_band": body.age_band if body.age_band is not None else existing.age_band,
        "language_code": body.language_code if body.language_code is not None else existing.language_code,
        "bedtime_mode_default": body.bedtime_mode_default if body.bedtime_mode_default is not None else existing.bedtime_mode_default,
        "microphone_enabled": body.microphone_enabled if body.microphone_enabled is not None else existing.microphone_enabled,
        "ar_enabled": body.ar_enabled if body.ar_enabled is not None else existing.ar_enabled,
    }
    try:
        privacy_service.lock_user(db, user.id)
        settings = privacy_repo.get_settings(db, user.id)
        privacy_service.require_core_storage(settings)
        profile = repo.upsert(db, user.id, merged)
        db.commit()
        return profile
    except PrivacyError as exc:
        db.rollback()
        raise HTTPException(status_code=exc.status_code, detail=exc.code) from exc
    except Exception:
        db.rollback()
        raise
