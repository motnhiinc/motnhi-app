from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ChildProfile


def list_for_user(db: Session, user_id: str) -> list[ChildProfile]:
    return list(db.scalars(select(ChildProfile).where(ChildProfile.user_id == user_id)))


def upsert(db: Session, user_id: str, data: dict) -> ChildProfile:
    now = datetime.now(timezone.utc)
    existing = db.get(ChildProfile, data["id"])
    if existing is not None and existing.user_id != user_id:
        existing = None  # treat as not-yours -> caller 404s
    if existing is None:
        profile = ChildProfile(id=data["id"], user_id=user_id, created_at=now, updated_at=now,
                               **{k: v for k, v in data.items() if k != "id"})
        db.add(profile)
    else:
        for k, v in data.items():
            if k != "id":
                setattr(existing, k, v)
        existing.updated_at = now
        profile = existing
    db.flush()
    return profile


def get_owned(db: Session, user_id: str, profile_id: str) -> ChildProfile | None:
    p = db.get(ChildProfile, profile_id)
    return p if p is not None and p.user_id == user_id else None
