from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import sessions as repo
from app.schemas import (
    EventOut,
    EventRequest,
    PatchSessionRequest,
    SessionOut,
    StartSessionRequest,
)

router = APIRouter(prefix="/v1/story-sessions", tags=["story-sessions"])


@router.post("", response_model=SessionOut)
def start_session(body: StartSessionRequest, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    if not repo._owns_profile(db, user.id, body.child_profile_id):
        raise HTTPException(status_code=404, detail="profile not found")
    return repo.start(db, body.story_id, body.child_profile_id, body.mode)


@router.get("", response_model=list[SessionOut])
def list_sessions(child_profile_id: str, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    return repo.list_for_child(db, user.id, child_profile_id)


@router.patch("/{session_id}", response_model=SessionOut)
def patch_session(session_id: str, body: PatchSessionRequest, db: Session = Depends(get_db),
                 user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.patch(db, s, body.last_page_number, body.completed)


@router.post("/{session_id}/events", response_model=EventOut)
def add_event(session_id: str, body: EventRequest, db: Session = Depends(get_db),
             user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.record_event(db, session_id, body.event_type, body.page_id, body.payload)


@router.get("/{session_id}/events", response_model=list[EventOut])
def get_events(session_id: str, db: Session = Depends(get_db),
              user: User = Depends(get_current_user)):
    s = repo.get_owned(db, user.id, session_id)
    if s is None:
        raise HTTPException(status_code=404, detail="session not found")
    return repo.list_events(db, session_id)
