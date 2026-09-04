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
    income = Decimal("0")
    expense = Decimal("0")
    pending = 0
    category_totals: dict[str, Decimal] = {}
    for row in rows:
        if row.deleted or row.occurred_on.strftime("%Y-%m") != month or row.kind == "transfer":
            continue
        if row.cny_amount is None:
            pending += 1
            continue
        value = money(row.cny_amount)
        if row.kind == "income":
            income += value
        elif row.kind == "expense":
            expense += value
            if row.category:
                category_totals[row.category] = category_totals.get(row.category, Decimal("0")) + value
    balance = income - expense
    savings_rate = money(balance / income * 100) if income else Decimal("0")
    return {
        "month": month,
        "income": money(income),
        "expense": money(expense),
        "balance": money(balance),
        "savings_rate": savings_rate,
        "category_totals": {key: money(value) for key, value in category_totals.items()},
        "pending_conversion_count": pending,
        "data_sufficient": bool(rows) and pending == 0,
    }


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
    """Build zero-filled, programmatic aggregates for chartable periods."""
    if end < start:
        raise ValueError("统计结束日期不能早于开始日期")
    day_mode = period == "day"
    buckets: list[datetime] = []
    if day_mode:
        buckets = [datetime.combine(start, time(hour=hour)) for hour in range(24)]
    else:
        cursor = start
        while cursor <= end:
            buckets.append(datetime.combine(cursor, time.min))
            cursor += timedelta(days=1)

    series = [
        {
            "bucket": bucket.isoformat(),
            "label": bucket.strftime("%H:%M" if day_mode else "%m-%d"),
            "expense": Decimal("0"),
            "income": Decimal("0"),
        }
        for bucket in buckets
    ]
    by_category: dict[str, Decimal] = {}
    by_account: dict[str, Decimal] = {}
    pending = 0
    income = Decimal("0")
    expense = Decimal("0")
    index = {bucket: position for position, bucket in enumerate(buckets)}
    for row in rows:
        if row.deleted or row.kind == "transfer":
            continue
        occurred = _record_datetime(row)
        if occurred.tzinfo is not None:
            occurred = occurred.replace(tzinfo=None)
        bucket_key = datetime.combine(occurred.date(), time.min) if not day_mode else occurred.replace(minute=0, second=0, microsecond=0)
        position = index.get(bucket_key)
        if position is None:
            continue
        if row.cny_amount is None:
            pending += 1
            continue
        value = money(row.cny_amount)
        if row.kind == "income":
            income += value
            series[position]["income"] += value
        elif row.kind == "expense":
            expense += value
            series[position]["expense"] += value
            category = row.category or "未分类"
            account = row.account_name or row.account_id or "未指定账户"
            by_category[category] = by_category.get(category, Decimal("0")) + value
            by_account[account] = by_account.get(account, Decimal("0")) + value
    return {
        "period_start": start,
        "period_end": end,
        "expense_total": money(expense),
        "expense_by_category": {key: money(value) for key, value in by_category.items()},
        "expense_by_account": {key: money(value) for key, value in by_account.items()},
        "expense_series": [
            {**point, "expense": money(point["expense"]), "income": money(point["income"])} for point in series
        ],
        "income_total": money(income),
        "net_worth_change": money(income - expense),
        "pending_conversion_count": pending,
    }


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
