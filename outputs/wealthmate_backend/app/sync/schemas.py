from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class SyncOperationIn(BaseModel):
    client_op_id: str
    entity: Literal["transactions", "accounts", "categories", "budgets"]
    entity_id: str
    type: Literal["upsert", "delete"]
    payload: dict[str, Any] = Field(default_factory=dict)
    created_at: str | None = None


class SyncPushIn(BaseModel):
    operations: list[SyncOperationIn] = Field(default_factory=list)
