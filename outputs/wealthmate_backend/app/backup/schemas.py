from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class BackupProfile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    display_name: str | None = Field(default=None, max_length=128)
    quick_memories: list[dict[str, Any]] | None = None


class RestoreIn(BaseModel):
    """V3 cloud-backup payload, while retaining the small V1 import shape."""

    model_config = ConfigDict(extra="forbid")

    kind: str | None = None
    schema_version: int | None = Field(default=None, ge=1, le=3)
    exported_at: str | datetime | None = None
    owner_id: str | None = Field(default=None, max_length=64)
    source_server_version: int | None = Field(default=None, ge=0)
    profile: BackupProfile | None = None
    accounts: list[dict[str, Any]] = Field(default_factory=list)
    categories: list[dict[str, Any]] = Field(default_factory=list)
    transactions: list[dict[str, Any]] = Field(default_factory=list)
    budgets: list[dict[str, Any]] = Field(default_factory=list)
    user_preferences: list[dict[str, Any]] = Field(default_factory=list, max_length=1)
    sync_operations: list[dict[str, Any]] = Field(default_factory=list)
    protocol_metadata: dict[str, Any] | None = None
    exchange_rates: list[dict[str, Any]] = Field(default_factory=list)
    net_worth_snapshots: list[dict[str, Any]] = Field(default_factory=list)
    account_mutation_audits: list[dict[str, Any]] = Field(default_factory=list)
    restore_id: str | None = Field(default=None, min_length=1, max_length=128)

    @model_validator(mode="after")
    def validate_contract(self) -> "RestoreIn":
        v3_fields = {"user_preferences", "sync_operations", "protocol_metadata", "exchange_rates",
                     "net_worth_snapshots", "account_mutation_audits"}
        if self.schema_version != 3 and v3_fields & self.model_fields_set:
            raise ValueError("V3 sections require schema_version 3")
        if self.schema_version in {2, 3}:
            if self.kind != "suixiangji.backup" or not self.owner_id:
                raise ValueError("Backup kind and owner_id are required")
            return self

        # V1 files were emitted without kind/schema metadata and only carried
        # accounts and transactions. A declared V1 version is accepted too,
        # but it cannot silently claim to contain newer backup sections.
        if self.schema_version == 1:
            if self.kind not in (None, "suixiangji.backup"):
                raise ValueError("invalid backup kind")
            if self.categories or self.budgets or self.profile is not None:
                raise ValueError("V1 backups only support accounts and transactions")
            return self

        if self.kind is not None or any(
            value is not None
            for value in (
                self.exported_at,
                self.owner_id,
                self.source_server_version,
                self.profile,
            )
        ):
            raise ValueError("backup metadata requires schema_version")
        if self.categories or self.budgets:
            raise ValueError("legacy backups only support accounts and transactions")
        return self
