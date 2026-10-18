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
    openai_api_key: str = ""
    openai_tts_model: str = "gpt-4o-mini-tts"
    openai_tts_voice: str = "coral"
    openai_tts_timeout_seconds: float = 30.0
    openai_page_validation_model: str = "gpt-4o-mini"
    openai_page_validation_timeout_seconds: float = 15.0
    openrouter_api_key: str = ""
    openrouter_page_model: str = "google/gemini-2.5-flash"
    openrouter_page_timeout_seconds: float = Field(default=25.0, gt=0, le=30)
    page_audio_concurrency: int = Field(default=3, ge=1, le=8)
    page_audio_process_concurrency: int = Field(default=6, ge=1, le=64)
    page_audio_queue_seconds: float = Field(default=5.0, gt=0)
    page_audio_deadline_seconds: float = Field(default=30.0, gt=0)
    page_audio_transient_retries: int = Field(default=1, ge=0, le=1)
    page_language_instructions_enabled: bool = True


settings = Settings()
