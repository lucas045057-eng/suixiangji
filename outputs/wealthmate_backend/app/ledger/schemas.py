from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, model_validator


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
    adjustment_meta: None = None
    reverses_transaction_id: None = None
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


class AdjustmentIn(TransactionIn):
    kind: Literal["adjustment"] = "adjustment"
    amount: Decimal = Field(allow_inf_nan=False, gt=-10**14, lt=10**14, decimal_places=6)
    currency: Literal["CNY"] = "CNY"
    cny_amount: Decimal = Field(allow_inf_nan=False, gt=-10**14, lt=10**14, decimal_places=6)
    exchange_rate: Decimal = Field(default=Decimal(1), ge=1, le=1)
    account_id: str = Field(min_length=1, max_length=64)
    category_id: None = None
    category_name: None = None
    from_account_id: None = None
    to_account_id: None = None
    adjustment_meta: dict
    reverses_transaction_id: str | None = Field(default=None, min_length=1, max_length=64)

    @model_validator(mode="after")
    def valid_delta(self):
        if self.amount == 0 or self.amount != self.cny_amount:
            raise ValueError("Adjustment requires an equal nonzero signed CNY delta")
        return self
