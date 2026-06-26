from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook"
    test_database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook_test"
    jwt_secret: str = "dev-only-not-for-prod-0123456789abcdef0123456789abcdef"
    jwt_algorithm: str = "HS256"
    asset_url_secret: str = "dev-asset-secret-0123456789abcdef0123456789abcdef"
    asset_url_ttl_seconds: int = 3600
    storage_dir: str = "storage"


settings = Settings()
