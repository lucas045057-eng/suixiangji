from functools import lru_cache
import re
from typing import Literal
from urllib.parse import urlparse

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
    demo_enabled: bool = False
    environment: Literal["development", "test", "beta", "production"] = "development"
    test_schema_init: bool = False
    auth_login_limit: int = Field(default=20, ge=1)
    auth_register_limit: int = Field(default=10, ge=1)
    llm_provider: str = "none"
    llm_model: str = ""
    llm_base_url: str = ""
    llm_api_key: str = ""
    frankfurter_base_url: str = "https://api.frankfurter.dev/v2"
    cors_origins: str = "*"
    app_latest_version: str = "1.0.4"
    app_latest_build: int = Field(default=7, ge=1)
    app_minimum_supported_version: str = "1.0.0"
    app_minimum_supported_build: int = Field(default=3, ge=1)
    app_force_update: bool = False
    app_download_url: str = ""
    app_release_notes: str = ""

    model_config = SettingsConfigDict(env_file=".env", env_prefix="WEALTHMATE_", extra="ignore")

    def validate_runtime(self) -> None:
        for field_name in ("app_latest_version", "app_minimum_supported_version"):
            value = getattr(self, field_name).strip()
            if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", value):
                raise ValueError(f"{field_name} must use numeric major.minor.patch format")
        download_url = self.app_download_url.strip()
        if download_url:
            parsed = urlparse(download_url)
            if parsed.scheme.lower() != "https" or not parsed.netloc:
                raise ValueError("app_download_url must be an HTTPS URL")
        if self.environment in ("beta", "production"):
            if len(self.jwt_secret) < 32 or self.jwt_secret.startswith(("change", "replace")):
                raise ValueError("Beta requires a unique strong JWT secret")
            if self.demo_enabled or self.test_schema_init:
                raise ValueError("Demo login and test schema initialization are forbidden in Beta")
            if "*" in self.cors_origins or not self.cors_origins.strip():
                raise ValueError("Beta requires explicit CORS origins")


@lru_cache
def get_settings() -> Settings:
    return Settings()
