import uuid
from datetime import datetime

from sqlalchemy import delete, distinct, exists, func, or_, select
from sqlalchemy.orm import Session

from app.models import (
    ChildProfile,
    ConsentEvent,
    InteractionEvent,
    PrivacySettings,
    Story,
    StorySession,
    User,
)


def get_settings(db: Session, user_id: str) -> PrivacySettings | None:
    return db.get(PrivacySettings, user_id)


def create_default_settings(
    db: Session, user_id: str, now: datetime
) -> PrivacySettings:
    settings = PrivacySettings(
        user_id=user_id,
        accepted_policy_version=None,
        core_storage_accepted_at=None,
        progress_tracking_enabled=False,
        cloud_tts_enabled=False,
        page_image_validation_enabled=False,
        last_active_at=now,
        updated_at=now,
    )
    db.add(settings)
    db.flush()
    return settings


def add_event(
    db: Session,
    user_id: str,
    scope: str,
    granted: bool,
    policy_version: str,
    now: datetime,
) -> ConsentEvent:
    event = ConsentEvent(
        id=str(uuid.uuid4()),
        user_id=user_id,
        scope=scope,
        granted=granted,
        policy_version=policy_version,
        created_at=now,
    )
    db.add(event)
    db.flush()
    return event


def data_counts(db: Session, user_id: str) -> dict[str, int]:
    child_profiles = db.scalar(
        select(func.count(distinct(ChildProfile.id))).where(
            ChildProfile.user_id == user_id
        )
    )
    authored_stories = db.scalar(
        select(func.count(distinct(Story.id))).where(Story.owner_user_id == user_id)
    )
    owned_session = or_(
        ChildProfile.user_id == user_id,
        Story.owner_user_id == user_id,
    )
    story_sessions = db.scalar(
        select(func.count(distinct(StorySession.id)))
        .join(ChildProfile, ChildProfile.id == StorySession.child_profile_id)
        .join(Story, Story.id == StorySession.story_id)
        .where(owned_session)
    )
    interaction_events = db.scalar(
        select(func.count(distinct(InteractionEvent.id)))
        .join(
            StorySession,
            StorySession.id == InteractionEvent.story_session_id,
        )
        .join(ChildProfile, ChildProfile.id == StorySession.child_profile_id)
        .join(Story, Story.id == StorySession.story_id)
        .where(owned_session)
    )
    return {
        "child_profiles": child_profiles or 0,
        "authored_stories": authored_stories or 0,
        "story_sessions": story_sessions or 0,
        "interaction_events": interaction_events or 0,
    }


def delete_reading_history(db: Session, user_id: str) -> int:
    owned_session = or_(
        ChildProfile.user_id == user_id,
        Story.owner_user_id == user_id,
    )
    session_ids = list(db.scalars(
        select(StorySession.id)
        .join(ChildProfile, ChildProfile.id == StorySession.child_profile_id)
        .join(Story, Story.id == StorySession.story_id)
        .where(owned_session)
    ))
    if not session_ids:
        return 0
    db.execute(
        delete(InteractionEvent).where(
            InteractionEvent.story_session_id.in_(session_ids)
        )
    )
    result = db.execute(
        delete(StorySession).where(StorySession.id.in_(session_ids))
    )
    db.flush()
    return result.rowcount


def retention_candidate_ids(db: Session, cutoff: datetime) -> list[str]:
    has_profile = exists().where(
        ChildProfile.user_id == PrivacySettings.user_id
    )
    has_authored_story = exists().where(
        Story.owner_user_id == PrivacySettings.user_id
    )
    return list(db.scalars(
        select(PrivacySettings.user_id).where(
            PrivacySettings.last_active_at < cutoff,
            or_(has_profile, has_authored_story),
        )
    ))


def missing_privacy_user_ids(db: Session) -> list[str]:
    has_settings = exists().where(PrivacySettings.user_id == User.id)
    return list(db.scalars(select(User.id).where(~has_settings)))
