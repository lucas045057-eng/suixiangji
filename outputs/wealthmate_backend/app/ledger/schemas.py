from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field


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
