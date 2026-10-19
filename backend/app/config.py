from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook"
    test_database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook_test"
    jwt_secret: str = "dev-only-not-for-prod-0123456789abcdef0123456789abcdef"
    jwt_algorithm: str = "HS256"
    asset_url_secret: str = "dev-asset-secret-0123456789abcdef0123456789abcdef"
    asset_url_ttl_seconds: int = 3600
    storage_dir: str = "storage"
    default_target_physical_width_mm: int = 210
    elevenlabs_api_key: str = ""
    elevenlabs_voice_id: str = "5yEPTrA0uAhZsBEhHjfi"
    elevenlabs_model_id: str = Field(default="eleven_flash_v2_5", min_length=1)
    elevenlabs_output_format: Literal["mp3_22050_32", "mp3_24000_48", "mp3_44100_32", "mp3_44100_64", "mp3_44100_96", "mp3_44100_128", "mp3_44100_192"] = "mp3_44100_64"
    elevenlabs_tts_timeout_seconds: float = Field(default=15.0, gt=0, le=60)
    elevenlabs_tts_debug_logging: bool = False
    google_vision_api_key: str = ""
    google_vision_timeout_seconds: float = Field(default=15.0, gt=0, le=30)
    scan_ocr_debug_logging: bool = True
    page_audio_concurrency: int = Field(default=6, ge=1, le=8)
    page_audio_process_concurrency: int = Field(default=6, ge=1, le=64)
    page_audio_queue_seconds: float = Field(default=5.0, gt=0)
    page_audio_deadline_seconds: float = Field(default=30.0, gt=0)
    page_audio_transient_retries: int = Field(default=1, ge=0, le=1)


settings = Settings()
