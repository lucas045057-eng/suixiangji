from __future__ import annotations

from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Any, TYPE_CHECKING

if TYPE_CHECKING:
    from ..domain import TransactionRecord


def monthly_metrics(rows: list[TransactionRecord], month: str) -> dict[str, Any]:
    """Return the legacy monthly aggregates without mutating any source data."""
    from ..domain import money

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
    from ..domain import money

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


# Short names are kept for the focused module tests; the API-compatible names
# above remain the canonical service boundary.
monthly_stats = monthly_metrics
period_stats = period_metrics
