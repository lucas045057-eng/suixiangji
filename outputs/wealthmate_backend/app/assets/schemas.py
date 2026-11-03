from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class AccountIn(BaseModel):
    id: str | None = None
    name: str = Field(min_length=1, max_length=128)
    note: str = Field(default='', max_length=256)
    archived_at: datetime | None = None
    kind: Literal["asset", "liability"] = "asset"
    account_kind: Literal[
        "cash",
        "bank_card",
        "wechat",
        "alipay",
        "foreign",
        "fund_investment",
        "credit_card",
        "loan",
        "other",
    ] = "other"
    currency: str = Field(default="CNY", min_length=3, max_length=16)
    opening_balance: Decimal = Decimal("0")
    opening_cny_amount: Decimal | None = None
    opening_exchange_rate: Decimal | None = None
    opening_rate_date: date | None = None
    opening_rate_source: str | None = None
    is_liquid: bool = False
    is_default_payment: bool = False


    @field_validator("archived_at", mode="before")
    @classmethod
    def validate_archived_at(cls, value):
        if value is None or isinstance(value, datetime):
            return value
        if not isinstance(value, str):
            raise ValueError("archived_at must be an ISO timestamp or NULL")
        return datetime.fromisoformat(value.replace("Z", "+00:00"))


class AccountPatch(AccountIn):
    name: str = Field(default=None, min_length=1, max_length=128)


class RateIn(BaseModel):
    base_currency: str
    quote_currency: str = "CNY"
    rate: Decimal = Field(gt=0)
    rate_date: date
    source: str
