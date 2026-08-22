from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict


class DeviceAuthRequest(BaseModel):
    device_id: str
    device_secret: str | None = None


class DeviceAuthResponse(BaseModel):
    token: str
    user_id: str
    device_secret: str | None = None  # set ONLY on first registration


class _ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class StoryOut(_ORM):
    id: str
    title: str
    slug: str
    description: str | None = None
    age_min: int
    age_max: int
    language_code: str
    duration_seconds: int
    cover_asset_id: str | None = None
    content_status: str
    rights_owner_id: str | None = None
    themes: list[str] = []
    is_downloaded: bool = False
    is_unlocked: bool = True
    is_authored: bool = False


class LibraryResponse(BaseModel):
    stories: list[StoryOut]


class PageOut(_ORM):
    id: str
    story_id: str
    page_number: int
    page_text: str | None = None
    page_image_asset_id: str | None = None
    image_target_id: str | None = None


class SegmentOut(_ORM):
    id: str
    story_id: str
    page_id: str
    speaker_key: str
    text: str
    voice_id: str
    emotion: str | None = None
    speed: float | None = None
    audio_asset_id: str | None = None
    start_ms: int | None = None
    end_ms: int | None = None
    sort_order: int


class ArSceneOut(_ORM):
    id: str
    story_id: str
    page_id: str
    status: str
    scene_json: dict[str, Any]


class ChoiceOut(_ORM):
    id: str
    label: str
    emoji: str | None = None
    is_correct: bool


class QuestionOut(_ORM):
    id: str
    page_id: str
    type: str
    prompt: str
    choices: list[ChoiceOut]


class StoryDetailResponse(BaseModel):
    story: StoryOut
    pages: list[PageOut]
    segments: list[SegmentOut]
    ar_scenes: list[ArSceneOut]
    questions: list[QuestionOut]


class ChildProfileIn(BaseModel):
    id: str
    nickname: str | None = None
    age_band: str
    language_code: str = "en"
    bedtime_mode_default: bool = False
    microphone_enabled: bool = False
    ar_enabled: bool = True


class ChildProfilePatch(BaseModel):
    nickname: str | None = None
    age_band: str | None = None
    language_code: str | None = None
    bedtime_mode_default: bool | None = None
    microphone_enabled: bool | None = None
    ar_enabled: bool | None = None


class ChildProfileOut(_ORM):
    id: str
    user_id: str
    nickname: str | None = None
    age_band: str
    language_code: str
    bedtime_mode_default: bool
    microphone_enabled: bool
    ar_enabled: bool


class StartSessionRequest(BaseModel):
    child_profile_id: str
    story_id: str
    mode: str = "library"


class PatchSessionRequest(BaseModel):
    last_page_number: int | None = None
    completed: bool | None = None


class SessionOut(_ORM):
    id: str
    child_profile_id: str
    story_id: str
    started_at: datetime
    completed_at: datetime | None = None
    last_page_number: int
    mode: str


class EventRequest(BaseModel):
    event_type: str
    page_id: str | None = None
    payload: dict[str, Any] = {}


class EventOut(_ORM):
    id: str
    story_session_id: str
    event_type: str
    page_id: str | None = None
    payload: dict[str, Any]
    created_at: datetime


class AssetSignRequest(BaseModel):
    asset_ids: list[str]


class ImageTargetEntry(BaseModel):
    page_id: str
    page_number: int
    image_target_id: str
    reference_image_url: str | None = None
    physical_width_mm: int


class ImageTargetManifest(BaseModel):
    story_id: str
    version: int
    targets: list[ImageTargetEntry]
