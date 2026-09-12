from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
from typing import Any


TWOPLACES = Decimal("0.01")


@dataclass(frozen=True)
class AccountRecord:
    id: str
    name: str
    kind: str
    balance: Decimal = Decimal("0")
    currency: str = "CNY"


@dataclass(frozen=True)
class TransactionRecord:
    id: str
    kind: str
    amount: Decimal
    currency: str
    cny_amount: Decimal | None
    category: str | None
    occurred_on: date
    account_id: str | None = None
    deleted: bool = False
    occurred_at: datetime | str | None = None
    account_name: str | None = None


def money(value: Decimal | int | float | str | None) -> Decimal:
    if value is None:
        return Decimal("0")
    return Decimal(str(value)).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def calculate_cny(amount: Decimal, currency: str, exchange_rate: Decimal | None, *, rate_date: date | None = None, source: str | None = None) -> dict[str, Any]:
    """Convert without guessing. The caller persists the returned snapshot fields."""
    amount = money(amount)
    currency = currency.upper()
    if currency == "CNY":
        return {
            "cny_amount": amount,
            "exchange_rate": Decimal("1"),
            "exchange_rate_date": rate_date,
            "exchange_rate_source": source or "CNY fixed rate",
            "conversion_status": "ready",
        }
    if exchange_rate is None or exchange_rate <= 0:
        return {
            "cny_amount": None,
            "exchange_rate": None,
            "exchange_rate_date": None,
            "exchange_rate_source": None,
            "conversion_status": "pending",
        }
    return {
        "cny_amount": money(amount * exchange_rate),
        "exchange_rate": exchange_rate,
        "exchange_rate_date": rate_date,
        "exchange_rate_source": source,
        "conversion_status": "ready",
    }


def _amount_from_text(text: str) -> Decimal | None:
    match = re.search(r"(?<!\d)(\d+(?:\.\d{1,2})?)(?:\s*)(?:元|块|人民币|CNY|USD|美元|刀)?", text, re.I)
    return money(match.group(1)) if match else None


def classify_natural_language(text: str, *, today: date | None = None) -> dict[str, Any]:
    """Rules-first parser. Its output is always a draft and must be confirmed by the user."""
    today = today or date.today()
    lowered = text.lower()
    kind = "income" if any(word in text for word in ("收入", "工资", "到账", "奖金", "收到")) else "expense"
    if any(word in text for word in ("转账", "转入", "转出")):
        kind = "transfer"
    currency = "USD" if any(word in lowered for word in ("usd", "美元")) else "CNY"
    category = None
    for keywords, label in (
        (("打车", "地铁", "公交", "交通"), "交通"),
        (("午饭", "晚饭", "早餐", "外卖", "餐饮", "吃饭"), "餐饮"),
        (("房租", "房贷"), "住房"),
        (("工资", "薪资"), "工资"),
        (("购物", "买了", "淘宝", "京东"), "购物"),
    ):
        if any(word in text for word in keywords):
            category = label
            break
    account = None
    for name in ("微信", "支付宝", "现金", "银行卡", "信用卡"):
        if name in text:
            account = name
            break
    occurred_on = today
    if "昨天" in text:
        occurred_on = today.fromordinal(today.toordinal() - 1)
    return {
        "kind": kind,
        "amount": _amount_from_text(text),
        "currency": currency,
        "category_hint": category,
        "account_hint": account,
        "occurred_on": occurred_on,
        "note": text.strip(),
        "confidence": 0.98 if category and account else 0.72,
        "requires_confirmation": True,
        "missing_fields": [field for field, value in (("amount", _amount_from_text(text)), ("account", account)) if value is None],
    }


def monthly_metrics(rows: list[TransactionRecord], month: str) -> dict[str, Any]:
    from .insights.domain import monthly_metrics as calculate_monthly_metrics

    return calculate_monthly_metrics(rows, month)


def _record_datetime(row: TransactionRecord) -> datetime:
    value = row.occurred_at
    if isinstance(value, datetime):
        return value
    if isinstance(value, str) and value:
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.combine(row.occurred_on, time.min)


def period_metrics(rows: list[TransactionRecord], period: str, start: date, end: date) -> dict[str, Any]:
    from .insights.domain import period_metrics as calculate_period_metrics

    return calculate_period_metrics(rows, period, start, end)


def push_idempotent(store: dict[str, dict[str, Any]], operations: dict[str, int], row: dict[str, Any], *, server_version: int) -> dict[str, Any]:
    """Reference implementation for the same idempotency contract used by the API."""
    op_id = row["client_op_id"]
    if op_id in operations:
        return {"created": False, "server_version": operations[op_id], "transaction": store[row["id"]]}
    server_version += 1
    store[row["id"]] = dict(row, server_version=server_version)
    operations[op_id] = server_version
    return {"created": True, "server_version": server_version, "transaction": store[row["id"]]}


def iso_date(value: date | datetime | None) -> str | None:
    return value.isoformat() if value else None
