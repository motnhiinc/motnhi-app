from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


# ---- runtime tables (server-generated UUID strings) ----
class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    email: Mapped[str | None] = mapped_column(Text, unique=True, nullable=True)
    auth_provider: Mapped[str] = mapped_column(Text, default="device")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    device_id: Mapped[str] = mapped_column(Text, unique=True, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    secret_hash: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class ChildProfile(Base):
    __tablename__ = "child_profiles"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    nickname: Mapped[str | None] = mapped_column(Text, nullable=True)
    age_band: Mapped[str] = mapped_column(Text)
    language_code: Mapped[str] = mapped_column(Text, default="en")
    bedtime_mode_default: Mapped[bool] = mapped_column(Boolean, default=False)
    microphone_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    ar_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class StorySession(Base):
    __tablename__ = "story_sessions"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    child_profile_id: Mapped[str] = mapped_column(ForeignKey("child_profiles.id"), index=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_page_number: Mapped[int] = mapped_column(Integer, default=0)
    mode: Mapped[str] = mapped_column(Text, default="library")


class InteractionEvent(Base):
    __tablename__ = "interaction_events"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_session_id: Mapped[str] = mapped_column(ForeignKey("story_sessions.id"), index=True)
    event_type: Mapped[str] = mapped_column(Text)
    page_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


# ---- content tables (TEXT natural ids, from seed) ----
class Story(Base):
    __tablename__ = "stories"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    title: Mapped[str] = mapped_column(Text)
    slug: Mapped[str] = mapped_column(Text, unique=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    age_min: Mapped[int] = mapped_column(Integer, default=3)
    age_max: Mapped[int] = mapped_column(Integer, default=8)
    language_code: Mapped[str] = mapped_column(Text, default="en")
    duration_seconds: Mapped[int] = mapped_column(Integer, default=0)
    cover_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    content_status: Mapped[str] = mapped_column(Text, default="published")
    rights_owner_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    themes: Mapped[list] = mapped_column(JSONB, default=list)

    pages: Mapped[list["StoryPage"]] = relationship(cascade="all, delete-orphan")
    segments: Mapped[list["NarrationSegment"]] = relationship(cascade="all, delete-orphan")
    ar_scenes: Mapped[list["ArScene"]] = relationship(cascade="all, delete-orphan")
    questions: Mapped[list["Question"]] = relationship(cascade="all, delete-orphan")


class StoryPage(Base):
    __tablename__ = "story_pages"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_number: Mapped[int] = mapped_column(Integer)
    page_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    page_image_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_target_id: Mapped[str | None] = mapped_column(Text, nullable=True)


class NarrationSegment(Base):
    __tablename__ = "narration_segments"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"), index=True)
    speaker_key: Mapped[str] = mapped_column(Text)
    text: Mapped[str] = mapped_column(Text)
    voice_id: Mapped[str] = mapped_column(Text)
    emotion: Mapped[str | None] = mapped_column(Text, nullable=True)
    speed: Mapped[float | None] = mapped_column(Numeric(4, 2), nullable=True)
    audio_asset_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    end_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sort_order: Mapped[int] = mapped_column(Integer)


class ArScene(Base):
    __tablename__ = "ar_scenes"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"), index=True)
    scene_json: Mapped[dict] = mapped_column(JSONB)
    status: Mapped[str] = mapped_column(Text, default="published")


class Question(Base):
    __tablename__ = "questions"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    story_id: Mapped[str] = mapped_column(ForeignKey("stories.id"), index=True)
    page_id: Mapped[str] = mapped_column(ForeignKey("story_pages.id"))
    type: Mapped[str] = mapped_column(Text)
    prompt: Mapped[str] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    choices: Mapped[list["QuestionChoice"]] = relationship(cascade="all, delete-orphan")


class QuestionChoice(Base):
    __tablename__ = "question_choices"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    question_id: Mapped[str] = mapped_column(ForeignKey("questions.id"), index=True)
    label: Mapped[str] = mapped_column(Text)
    emoji: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_correct: Mapped[bool] = mapped_column(Boolean, default=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
