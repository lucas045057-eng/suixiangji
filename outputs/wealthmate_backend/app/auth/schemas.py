from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class LoginIn(BaseModel):
    username: str
    password: str


class ProfilePatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=128)
    username: str | None = Field(default=None, min_length=3, max_length=128)
    quick_memories: list[dict[str, Any]] | None = None


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)
