from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


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


class AccountIn(BaseModel):
    id: str | None = None
    name: str = Field(min_length=1, max_length=128)
    kind: Literal["asset", "liability"] = "asset"
    account_kind: Literal["cash", "bank_card", "wechat", "alipay", "foreign", "fund_investment", "credit_card", "loan", "other"] = "other"
    currency: str = Field(default="CNY", min_length=3, max_length=16)
    opening_balance: Decimal = Decimal("0")
    opening_cny_amount: Decimal | None = None
    opening_exchange_rate: Decimal | None = None
    opening_rate_date: date | None = None
    opening_rate_source: str | None = None
    is_liquid: bool = False
    is_default_payment: bool = False


class CategoryIn(BaseModel):
    id: str | None = None
    name: str = Field(min_length=1, max_length=128)
    kind: Literal["income", "expense"] = "expense"


class CategoryPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    active: bool | None = None


class TransactionIn(BaseModel):
    id: str | None = None
    client_op_id: str
    kind: Literal["income", "expense", "transfer"]
    amount: Decimal = Field(gt=0)
    currency: str = Field(default="CNY", min_length=3, max_length=16)
    cny_amount: Decimal | None = None
    exchange_rate: Decimal | None = None
    exchange_rate_date: date | None = None
    exchange_rate_source: str | None = None
    category_id: str | None = None
    category_name: str | None = None
    account_id: str | None = None
    from_account_id: str | None = None
    to_account_id: str | None = None
    occurred_on: date
    occurred_at: str | None = None
    note: str | None = None


class SyncOperationIn(BaseModel):
    client_op_id: str
    entity: Literal["transactions", "accounts", "categories", "budgets"]
    entity_id: str
    type: Literal["upsert", "delete"]
    payload: dict[str, Any] = Field(default_factory=dict)
    created_at: str | None = None


class SyncPushIn(BaseModel):
    operations: list[SyncOperationIn] = Field(default_factory=list)


class RestoreIn(BaseModel):
    model_config = ConfigDict(extra="allow")
    accounts: list[dict[str, Any]] = Field(default_factory=list)
    transactions: list[dict[str, Any]] = Field(default_factory=list)


class DraftIn(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


class RateIn(BaseModel):
    base_currency: str
    quote_currency: str = "CNY"
    rate: Decimal = Field(gt=0)
    rate_date: date
    source: str


class BudgetIn(BaseModel):
    id: str | None = None
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    category_id: str = Field(min_length=1, max_length=64)
    limit: Decimal = Field(gt=0)
    active: bool = True


class BudgetPatch(BaseModel):
    month: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}$")
    category_id: str | None = Field(default=None, min_length=1, max_length=64)
    limit: Decimal | None = Field(default=None, gt=0)
    active: bool | None = None
