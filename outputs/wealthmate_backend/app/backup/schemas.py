from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class RestoreIn(BaseModel):
    model_config = ConfigDict(extra="allow")
    accounts: list[dict[str, Any]] = Field(default_factory=list)
    transactions: list[dict[str, Any]] = Field(default_factory=list)
