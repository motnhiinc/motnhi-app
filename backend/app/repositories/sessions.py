import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ChildProfile, InteractionEvent, StorySession


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _owns_profile(db: Session, user_id: str, child_profile_id: str) -> bool:
    p = db.get(ChildProfile, child_profile_id)
    return p is not None and p.user_id == user_id


def record_event(db: Session, session_id: str, event_type: str,
                 page_id: str | None = None, payload: dict | None = None) -> InteractionEvent:
    event = InteractionEvent(id=str(uuid.uuid4()), story_session_id=session_id,
                             event_type=event_type, page_id=page_id,
                             payload=payload or {}, created_at=_now())
    db.add(event)
    db.commit()
    return event


def start(db: Session, story_id: str, child_profile_id: str, mode: str) -> StorySession:
    s = StorySession(id=str(uuid.uuid4()), child_profile_id=child_profile_id,
                     story_id=story_id, started_at=_now(), mode=mode)
    db.add(s)
    db.commit()
    record_event(db, s.id, "story_started", payload={"story_id": story_id, "mode": mode})
    return s


def get_owned(db: Session, user_id: str, session_id: str) -> StorySession | None:
    s = db.get(StorySession, session_id)
    if s is None or not _owns_profile(db, user_id, s.child_profile_id):
        return None
    return s


def patch(db: Session, s: StorySession, last_page_number: int | None, completed: bool | None) -> StorySession:
    if last_page_number is not None:
        s.last_page_number = last_page_number
    newly_completed = bool(completed) and s.completed_at is None
    if newly_completed:
        s.completed_at = _now()
    db.commit()
    if newly_completed:
        record_event(db, s.id, "story_completed")
    return s


def list_for_child(db: Session, user_id: str, child_profile_id: str) -> list[StorySession]:
    if not _owns_profile(db, user_id, child_profile_id):
        return []
    return list(db.scalars(select(StorySession).where(StorySession.child_profile_id == child_profile_id)))


def list_events(db: Session, session_id: str) -> list[InteractionEvent]:
    return list(db.scalars(select(InteractionEvent)
                           .where(InteractionEvent.story_session_id == session_id)
                           .order_by(InteractionEvent.created_at)))
