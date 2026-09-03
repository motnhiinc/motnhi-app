from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from app.models import (
    ArScene,
    ChildProfile,
    ConsentEvent,
    InteractionEvent,
    NarrationSegment,
    PrivacySettings,
    Question,
    QuestionChoice,
    Story,
    StoryPage,
    StorySession,
)


def delete_child_data(db: Session, user_id: str) -> None:
    """Delete every child-data row the user owns without committing.

    FK-safe order, children before the rows they reference: interaction
    events -> story sessions -> authored question choices -> authored
    questions / AR scenes / narration segments -> authored story pages ->
    authored stories -> child profiles -> consent events -> privacy
    settings. User and device rows survive; curated stories (owner_user_id
    IS NULL) are never touched. The caller owns the transaction.
    """
    owned_session_ids = (
        select(StorySession.id)
        .join(ChildProfile, ChildProfile.id == StorySession.child_profile_id)
        .join(Story, Story.id == StorySession.story_id)
        .where(or_(ChildProfile.user_id == user_id, Story.owner_user_id == user_id))
    )
    db.execute(delete(InteractionEvent).where(
        InteractionEvent.story_session_id.in_(owned_session_ids)
    ))
    db.execute(delete(StorySession).where(StorySession.id.in_(owned_session_ids)))

    authored_story_ids = select(Story.id).where(Story.owner_user_id == user_id)
    authored_question_ids = select(Question.id).where(
        Question.story_id.in_(authored_story_ids)
    )
    db.execute(delete(QuestionChoice).where(
        QuestionChoice.question_id.in_(authored_question_ids)
    ))
    db.execute(delete(Question).where(Question.story_id.in_(authored_story_ids)))
    db.execute(delete(ArScene).where(ArScene.story_id.in_(authored_story_ids)))
    db.execute(delete(NarrationSegment).where(
        NarrationSegment.story_id.in_(authored_story_ids)
    ))
    db.execute(delete(StoryPage).where(StoryPage.story_id.in_(authored_story_ids)))
    db.execute(delete(Story).where(Story.owner_user_id == user_id))

    db.execute(delete(ChildProfile).where(ChildProfile.user_id == user_id))
    db.execute(delete(ConsentEvent).where(ConsentEvent.user_id == user_id))
    db.execute(delete(PrivacySettings).where(PrivacySettings.user_id == user_id))
    db.flush()
