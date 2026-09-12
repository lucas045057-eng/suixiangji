from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import Any


TWOPLACES = Decimal("0.01")


def money(value: Decimal | int | float | str | None) -> Decimal:
    if value is None:
        return Decimal("0")
    return Decimal(str(value)).quantize(TWOPLACES, rounding=ROUND_HALF_UP)


def calculate_cny(
    amount: Decimal,
    currency: str,
    exchange_rate: Decimal | None,
    *,
    rate_date: date | None = None,
    source: str | None = None,
) -> dict[str, Any]:
    """Convert without guessing and preserve the exact rate snapshot."""
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


def date_value(value: str | date | None, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if value:
        return date.fromisoformat(value[:10])
    return fallback or date.today()


def json_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_value(item) for item in value]
    return value
