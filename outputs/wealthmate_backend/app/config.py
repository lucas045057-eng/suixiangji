from functools import lru_cache

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "随想记 V1 API"
    git_sha: str = Field(default="unknown", validation_alias=AliasChoices("APP_GIT_SHA", "WEALTHMATE_GIT_SHA"))
    database_url: str = "sqlite:///./wealthmate.db"
    jwt_secret: str = "change-this-before-deployment"
    jwt_expire_minutes: int = 60 * 24 * 30
    demo_username: str = "admin"
    demo_password: str = "change-me"
    llm_provider: str = "none"
    llm_model: str = ""
    llm_base_url: str = ""
    llm_api_key: str = ""
    frankfurter_base_url: str = "https://api.frankfurter.dev/v2"
    cors_origins: str = "*"

    model_config = SettingsConfigDict(env_file=".env", env_prefix="WEALTHMATE_", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
