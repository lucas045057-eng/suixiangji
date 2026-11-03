"""Typed v3 storage boundary; ordinary ledger endpoints remain immutable."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from ..assets.schemas import AccountIn
from ..budget.schemas import BudgetIn
from ..ledger.schemas import TransactionIn, AdjustmentIn, CategoryIn

MAX_VERSION = 2**31 - 1


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AccountRecord(AccountIn, Strict):
    id: str = Field(min_length=1, max_length=64)
    deleted_at: datetime | None = None


class CategoryRecord(CategoryIn, Strict):
    id: str = Field(min_length=1, max_length=64)
    active: bool = True


class BudgetRecord(BudgetIn, Strict):
    id: str = Field(min_length=1, max_length=64)
    deleted_at: datetime | None = None


class TransactionRecord(TransactionIn, Strict):
    id: str = Field(min_length=1, max_length=64)
    conversion_status: Literal["ready", "pending"] = "ready"
    deleted_at: datetime | None = None


class AdjustmentRecord(AdjustmentIn, Strict):
    id: str = Field(min_length=1, max_length=64)
    conversion_status: Literal["ready"] = "ready"
    deleted_at: None = None


class PreferenceRecord(Strict):
    id: Literal["self"] = "self"
    default_account_id: str | None = Field(default=None, min_length=1, max_length=64)
    server_version: int = Field(default=0, ge=0, le=MAX_VERSION)
    updated_at: datetime | None = None


class ProtocolRecord(Strict):
    sync_protocol: Literal[2] = 2
    min_client_protocol: int = Field(ge=1, le=MAX_VERSION)
    financial_model: Literal["cny_adjustments_v1"] = "cny_adjustments_v1"


class ReceiptRecord(Strict):
    client_op_id: str = Field(min_length=1, max_length=128)
    entity: str = Field(min_length=1, max_length=64)
    entity_id: str = Field(min_length=1, max_length=64)
    server_version: int = Field(ge=0, le=MAX_VERSION)
    protocol_version: Literal[1, 2] = 1
    request_hash: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")
    result_json: dict[str, Any] | None = None
    created_at: datetime


class RateRecord(Strict):
    base_currency: str = Field(min_length=3, max_length=16, pattern=r"^[A-Z]+$")
    quote_currency: str = Field(min_length=3, max_length=16, pattern=r"^[A-Z]+$")
    rate: Decimal = Field(gt=0)
    rate_date: date
    source: str = Field(min_length=1, max_length=256)
    fetched_at: datetime


class NetWorthRecord(Strict):
    month: str = Field(pattern=r"^\d{4}-(?:0[1-9]|1[0-2])$")
    total_assets_cny: Decimal | None
    total_liabilities_cny: Decimal | None
    net_worth_cny: Decimal | None
    pending_conversion_count: int = Field(ge=0, le=MAX_VERSION)
    created_at: datetime


class AuditRecord(Strict):
    account_id: str = Field(min_length=1, max_length=64)
    client_op_id: str = Field(min_length=1, max_length=128)
    event_kind: str = Field(min_length=1, max_length=64)
    before_json: dict[str, Any]
    after_json: dict[str, Any]
    reason: str
    created_at: datetime
