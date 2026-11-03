from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class SyncOperationIn(BaseModel):
    client_op_id: str
    entity: Literal["transactions", "accounts", "categories", "budgets"]
    entity_id: str
    type: Literal["upsert", "delete"]
    payload: dict[str, Any] = Field(default_factory=dict)
    created_at: str | None = None


class SyncPushIn(BaseModel):
    operations: list[SyncOperationIn] = Field(default_factory=list)


class SyncOperationV2In(BaseModel):
    client_op_id: str = Field(min_length=1, max_length=128)
    entity: str = Field(min_length=1, max_length=64)
    entity_id: str = Field(min_length=1, max_length=64)
    type: Literal["upsert", "delete"]
    payload: dict[str, Any] = Field(default_factory=dict)
    base_version: Any = None
    base: Any = None

    @field_validator("client_op_id", "entity", "entity_id")
    @classmethod
    def valid_identifier(cls, value):
        if "\x00" in value:
            raise ValueError("NUL characters are not supported in identifiers")
        return value


class SyncPushV2In(BaseModel):
    operations: list[SyncOperationV2In] = Field(default_factory=list, max_length=1000)

    @model_validator(mode="after")
    def unique_operations(self):
        ids = [op.client_op_id for op in self.operations]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate client_op_id in batch")
        return self
