from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import ArScene, NarrationSegment, Question, Story, StoryPage

# Age bands -> (min, max) per enums.dart
_BANDS = {"3-4": (3, 4), "5-6": (5, 6), "7-8": (7, 8)}


def list_published(db: Session, age_band: str | None, language: str | None) -> list[Story]:
    stmt = select(Story).where(Story.content_status == "published")
    if language:
        stmt = stmt.where(Story.language_code == language)
    stories = list(db.scalars(stmt))
    if age_band and age_band in _BANDS:
        lo, hi = _BANDS[age_band]
        stories = [s for s in stories if s.age_min <= hi and s.age_max >= lo]
    return stories


def get_detail(db: Session, story_id: str) -> dict | None:
    story = db.get(Story, story_id)
    if story is None:
        return None
    pages = list(db.scalars(select(StoryPage).where(StoryPage.story_id == story_id)
                            .order_by(StoryPage.page_number)))
    segments = list(db.scalars(select(NarrationSegment).where(NarrationSegment.story_id == story_id)
                               .order_by(NarrationSegment.sort_order)))
    ar_scenes = list(db.scalars(select(ArScene).where(ArScene.story_id == story_id)))
    questions = list(db.scalars(select(Question).where(Question.story_id == story_id)
                                .order_by(Question.sort_order)))
    return {"story": story, "pages": pages, "segments": segments,
            "ar_scenes": ar_scenes, "questions": questions}
