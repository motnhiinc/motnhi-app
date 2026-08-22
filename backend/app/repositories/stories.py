from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import ArScene, NarrationSegment, Question, Story, StoryPage

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
