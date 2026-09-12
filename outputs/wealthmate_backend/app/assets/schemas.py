from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field


class AccountIn(BaseModel):
    id: str | None = None
    name: str = Field(min_length=1, max_length=128)
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


class RateIn(BaseModel):
    base_currency: str
    quote_currency: str = "CNY"
    rate: Decimal = Field(gt=0)
    rate_date: date
    source: str
