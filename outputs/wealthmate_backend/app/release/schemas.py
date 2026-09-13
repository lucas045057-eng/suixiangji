from pydantic import BaseModel, Field


class AppVersionResponse(BaseModel):
    latest_version: str
    latest_build: int = Field(ge=1)
    minimum_supported_version: str
    minimum_supported_build: int = Field(ge=1)
    force_update: bool
    download_url: str | None
    release_notes: str
