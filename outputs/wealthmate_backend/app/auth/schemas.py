from __future__ import annotations

import re
from typing import Any

from pydantic import BaseModel, Field, field_validator


def normalized_username(value: str) -> str:
    value = value.strip()
    if not re.fullmatch(r"[a-zA-Z0-9_-]{3,32}", value, flags=re.ASCII):
        raise ValueError("用户名须为3–32位英文字母、数字、下划线或连字符")
    return value.lower()


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=256)
    password: str = Field(min_length=1, max_length=256)


class RegisterIn(BaseModel):
    username: str
    password: str = Field(min_length=8, max_length=256)
    display_name: str | None = Field(default=None, max_length=128)
    invite_code: str = Field(min_length=1, max_length=128)

    _username = field_validator("username")(normalized_username)


class DeleteUserIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)


class ProfilePatch(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=128)
    username: str | None = Field(default=None, min_length=3, max_length=128)
    quick_memories: list[dict[str, Any]] | None = None

    @field_validator("username")
    @classmethod
    def validate_username(cls, value: str | None) -> str | None:
        return normalized_username(value) if value is not None else None


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)
