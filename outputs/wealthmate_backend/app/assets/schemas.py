from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field, field_validator, ConfigDict


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


class CalibrationIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_op_id: str = Field(min_length=1, max_length=128)
    adjustment_id: str = Field(min_length=1, max_length=64)
    target_cny: Decimal = Field(allow_inf_nan=False, gt=-10**14, lt=10**14, decimal_places=2)
    expected_current_cny: Decimal = Field(allow_inf_nan=False, gt=-10**14, lt=10**14, decimal_places=6)
    effective_on: date

    @field_validator("effective_on", mode="before")
    @classmethod
    def business_date(cls, value):
        if isinstance(value, str):
            value = date.fromisoformat(value)
        if type(value) is not date or value > date.today():
            raise ValueError("effective_on must be a non-future business date")
        return value


class ReverseCalibrationIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_op_id: str = Field(min_length=1, max_length=128)
    adjustment_id: str = Field(min_length=1, max_length=64)
    effective_on: date = Field(default_factory=date.today)
    _date = field_validator("effective_on", mode="before")(CalibrationIn.business_date.__func__)
