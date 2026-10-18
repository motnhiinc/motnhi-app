import uuid

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import (
    ArScene,
    InteractionEvent,
    NarrationSegment,
    Question,
    Story,
    StoryPage,
    StorySession,
)

# Age bands -> (min, max) per enums.dart
_BANDS = {"3-4": (3, 4), "5-6": (5, 6), "7-8": (7, 8)}


def _visible_to(user_id: str):
    """Curated stories (no owner) plus this user's own authored stories."""
    return or_(Story.owner_user_id.is_(None), Story.owner_user_id == user_id)


def list_published(db: Session, user_id: str, age_band: str | None,
                   language: str | None) -> list[Story]:
    stmt = select(Story).where(Story.content_status == "published", _visible_to(user_id))
    if language:
        stmt = stmt.where(Story.language_code == language)
    stories = list(db.scalars(stmt))
    if age_band and age_band in _BANDS:
        lo, hi = _BANDS[age_band]
        stories = [s for s in stories if s.age_min <= hi and s.age_max >= lo]
    return stories


def get_detail(db: Session, user_id: str, story_id: str) -> dict | None:
    story = db.get(Story, story_id)
    if story is None:
        return None
    if story.owner_user_id is not None and story.owner_user_id != user_id:
        return None  # 404, not 403 - a 403 confirms the id exists
    pages = list(db.scalars(select(StoryPage).where(StoryPage.story_id == story_id)
                            .order_by(StoryPage.page_number)))
    segments = list(db.scalars(select(NarrationSegment).where(NarrationSegment.story_id == story_id)
                               .order_by(NarrationSegment.sort_order)))
    ar_scenes = list(db.scalars(select(ArScene).where(ArScene.story_id == story_id)))
    questions = list(db.scalars(select(Question).where(Question.story_id == story_id)
                                .order_by(Question.sort_order)))
    return {"story": story, "pages": pages, "segments": segments,
            "ar_scenes": ar_scenes, "questions": questions}


_WORDS_PER_MINUTE = 130
MAX_AUTHORED_PER_USER = 100


def count_authored(db: Session, user_id: str) -> int:
    return len(list(db.scalars(select(Story.id).where(Story.owner_user_id == user_id))))


def _estimated_duration_seconds(texts: list[str]) -> int:
    words = sum(len(t.split()) for t in texts)
    return max(60, round(words / _WORDS_PER_MINUTE * 60))


def create_authored(db: Session, user_id: str, payload) -> Story:
    """Write story + pages + one narration segment per page in one transaction.

    One segment per page, with a null audio_asset_id, is what makes an authored
    story deserialise into exactly the same StoryDetail shape as a curated one:
    the client player needs no structural change, and the null asset id routes
    playback to the per-read TTS path.
    """
    ordered = sorted(payload.pages, key=lambda p: p.page_number)
    story_id = str(uuid.uuid4())
    story = Story(
        id=story_id,
        title=payload.title,
        slug=f"authored-{uuid.uuid4()}",
        description=None,
        age_min=3,
        age_max=8,
        language_code=payload.language_code,
        duration_seconds=_estimated_duration_seconds([p.page_text for p in ordered]),
        cover_asset_id=None,
        content_status="published",
        rights_owner_id=None,
        themes=[],
        owner_user_id=user_id,
    )
    db.add(story)
    db.flush()

    for page in ordered:
        page_id = str(uuid.uuid4())
        db.add(StoryPage(
            id=page_id, story_id=story_id, page_number=page.page_number,
            page_text=page.page_text, page_image_asset_id=None, image_target_id=None,
        ))
        db.flush()
        db.add(NarrationSegment(
            id=str(uuid.uuid4()), story_id=story_id, page_id=page_id,
            speaker_key="narrator", text=page.page_text,
            voice_id=settings.elevenlabs_voice_id, emotion=None, speed=1.0,
            audio_asset_id=None, start_ms=0, end_ms=0, sort_order=0,
        ))
    db.flush()
    db.refresh(story)
    return story


def delete_authored(db: Session, user_id: str, story_id: str) -> bool:
    """Delete a story the user authored.

    Returns False when the story is unknown, curated, or owned by someone else;
    the router turns that into a 404 rather than a 403, so the endpoint never
    confirms that an id exists.
    """
    story = db.get(Story, story_id)
    if story is None or story.owner_user_id != user_id:
        return False

    # story_sessions.story_id is a bare FK with no ondelete, and Story has no
    # ORM relationship to StorySession, so nothing cascades here. Clear the
    # sessions and their events first or Postgres raises an IntegrityError for
    # any story that was ever opened in the player.
    session_ids = list(db.scalars(
        select(StorySession.id).where(StorySession.story_id == story_id)
    ))
    if session_ids:
        db.query(InteractionEvent).filter(
            InteractionEvent.story_session_id.in_(session_ids)
        ).delete(synchronize_session=False)
        db.query(StorySession).filter(
            StorySession.id.in_(session_ids)
        ).delete(synchronize_session=False)

    # pages / segments / ar_scenes / questions go via the cascade="all,
    # delete-orphan" relationships declared on the Story model.
    db.delete(story)
    db.flush()
    return True
