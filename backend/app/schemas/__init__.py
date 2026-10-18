from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    model_validator,
)


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


AuthoredTitle = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)
]
AuthoredPageText = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)
]


class CreateStoryPage(BaseModel):
    page_number: int = Field(ge=1, le=50)
    page_text: AuthoredPageText


class CreateStoryRequest(BaseModel):
    """Body of POST /v1/stories. Page numbers must be contiguous 1..N so the
    client's orderedPages and last_page_number stay unambiguous."""

    title: AuthoredTitle
    language_code: str = "en"
    pages: list[CreateStoryPage] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def _check(self) -> "CreateStoryRequest":
        if self.language_code not in ("en", "vi"):
            raise ValueError("language_code must be 'en' or 'vi'")
        numbers = [p.page_number for p in self.pages]
        if sorted(numbers) != list(range(1, len(numbers) + 1)):
            raise ValueError("page_number must be contiguous 1..N with no duplicates")
        return self


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


class PrivacyUpdateRequest(BaseModel):
    policy_version: str
    core_storage_accepted: bool
    progress_tracking_enabled: bool
    cloud_tts_enabled: bool
    page_image_validation_enabled: bool


class PrivacyDataCounts(BaseModel):
    child_profiles: int
    authored_stories: int
    story_sessions: int
    interaction_events: int


class PrivacyStateResponse(BaseModel):
    current_policy_version: str
    accepted_policy_version: str | None
    review_required: bool
    core_storage_accepted_at: datetime | None
    progress_tracking_enabled: bool
    cloud_tts_enabled: bool
    page_image_validation_enabled: bool
    effective_progress_tracking_enabled: bool
    effective_cloud_tts_enabled: bool
    effective_page_image_validation_enabled: bool
    last_active_at: datetime
    updated_at: datetime
    counts: PrivacyDataCounts


class PageLine(BaseModel):
    text: str = Field(min_length=1, max_length=4000)
    left: float = Field(ge=0, le=1, allow_inf_nan=False)
    top: float = Field(ge=0, le=1, allow_inf_nan=False)
    width: float = Field(gt=0, le=1, allow_inf_nan=False)
    height: float = Field(gt=0, le=1, allow_inf_nan=False)

    @model_validator(mode="after")
    def inside_page(self):
        if self.left + self.width > 1.000001 or self.top + self.height > 1.000001:
            raise ValueError("box outside page")
        return self


class ValidatePageRequest(BaseModel):
    profile_id: str
    correct_ocr: bool = False
    content_language: Literal["vi", "en"] | None = None
    image_base64: str
    lines: list[PageLine] = Field(min_length=1, max_length=40)

    @model_validator(mode="after")
    def text_limit(self):
        if sum(len(line.text) for line in self.lines) > 4000:
            raise ValueError("page text too long")
        return self


class PageAudioRequest(BaseModel):
    profile_id: str
    content_language: Literal["vi", "en"] | None = None
    proof: str
    lines: list[str] = Field(min_length=1, max_length=40)

    @model_validator(mode="after")
    def text_limit(self):
        if any(not line.strip() or len(line) > 4000 for line in self.lines):
            raise ValueError("invalid line")
        if sum(len(line) for line in self.lines) > 4000:
            raise ValueError("page text too long")
        return self
