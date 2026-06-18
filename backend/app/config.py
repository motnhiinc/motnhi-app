from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook"
    test_database_url: str = "postgresql+psycopg://storybook:storybook@localhost:5432/storybook_test"
    jwt_secret: str = "dev-secret-change-me"
    jwt_algorithm: str = "HS256"


settings = Settings()
