"""Version 1 wire schema and the separate, untrusted LLM semantic plan."""
from __future__ import annotations

import re
from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, StringConstraints


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


def _iso_date(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise ValueError("Expected an ISO calendar date")
    return date.fromisoformat(value)


ISODate = Annotated[date, BeforeValidator(_iso_date)]
Currency = Annotated[str, StringConstraints(pattern=r"^[A-Z]{3}$")]
MoneyText = Annotated[
    str, StringConstraints(pattern=r"^[0-9]{1,20}(?:\.[0-9]{1,6})?$")
]
Hint = Annotated[str, StringConstraints(min_length=1, max_length=128)]


class CategoryTotal(StrictModel):
    category_id: Annotated[str, Field(min_length=1, max_length=64)]
    category_name: Hint
    expense_total: MoneyText


class TargetDay(StrictModel):
    expense_total: MoneyText
    expense_count: Annotated[int, Field(ge=0)]


class ReferenceDay(TargetDay):
    category_totals: list[CategoryTotal]


class CurrencyContext(StrictModel):
    currency: Currency
    reference_day: ReferenceDay
    target_day: TargetDay


class ReadyContext(StrictModel):
    status: Literal["ready"]
    target_date: ISODate
    reference_date: ISODate
    fingerprint: Annotated[str, Field(max_length=256)]
    currencies: list[CurrencyContext]


class UnavailableContext(StrictModel):
    status: Literal["unavailable"]


def _schema_version(value):
    if type(value) is not int:
        raise ValueError("Expected an integer schema version")
    return value


class DraftsIn(StrictModel):
    schema_version: Annotated[Literal[1], BeforeValidator(_schema_version)]
    request_id: Annotated[str, StringConstraints(min_length=8, max_length=64)]
    text: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)
    ]
    local_today: ISODate
    utc_offset_minutes: Annotated[int, Field(ge=-840, le=840)]
    preferred_currency: Currency
    ledger_context: Annotated[
        ReadyContext | UnavailableContext, Field(discriminator="status")
    ] | None = None


class SourceQuote(StrictModel):
    quote: Annotated[str, StringConstraints(min_length=1, max_length=1000)]
    start: Annotated[int, Field(ge=0)]
    end: Annotated[int, Field(gt=0)]


class SemanticRange(StrictModel):
    lower: MoneyText
    upper: MoneyText
    lower_inclusive: bool = True
    upper_inclusive: bool = False


class SemanticItem(SourceQuote):
    type: Literal["expense", "income", "transfer"]
    amount_kind: Literal["exact", "bounded_range", "missing"]
    amount_exact: MoneyText | None = None
    range: SemanticRange | None = None
    currency: Currency | None = None
    date_relation: Literal["today", "yesterday", "explicit"]
    date: ISODate | None = None
    category_hint: Hint | None = None
    account_hint: Hint | None = None
    note: Annotated[str, StringConstraints(max_length=256)] = ""


class SemanticReference(SourceQuote):
    kind: Literal["previous_day_total_expense", "previous_day_category_expense"]
    category_hint: Hint | None = None
    currency: Currency | None = None


class SemanticPlan(StrictModel):
    items: list[SemanticItem]
    reference: SemanticReference | None = None
    has_more_than_8_items: bool
    unresolved: list[
        Literal["unsupported_reference", "transfer", "ambiguous_currency", "ambiguous_total"]
    ]


class BatchError(Exception):
    """Only fixed, display-safe messages may cross the HTTP boundary."""

    MESSAGES = {
        "invalid_context": (400, "账本聚合上下文不一致，请刷新后重试"),
        "text_too_large": (413, "文本过长，请缩短到1000字以内"),
        "validation_error": (422, "请求格式不正确，请检查输入"),
        "rate_limited": (429, "解析过于频繁，请稍后再试"),
        "llm_bad_response": (502, "AI解析结果无效，请手动确认"),
        "llm_unavailable": (503, "AI服务暂不可用，请手动确认"),
        "llm_timeout": (504, "AI解析超时，请手动确认"),
        "internal_error": (500, "解析服务暂时出错，请稍后再试"),
    }

    def __init__(self, code: str):
        self.code = code
        self.status_code, self.detail = self.MESSAGES[code]
        super().__init__(code)
