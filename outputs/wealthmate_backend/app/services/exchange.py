from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any

import httpx

from ..config import get_settings


def parse_frankfurter_response(payload: Any, base: str, quote: str) -> tuple[Decimal, date]:
    """Accept the v2 row shape and the older map shape without inventing a rate."""
    if isinstance(payload, list) and payload:
        row = payload[0]
        rate = row.get("rate")
        rate_date = row.get("date")
        if rate is not None and rate_date:
            return Decimal(str(rate)), date.fromisoformat(rate_date)
    if isinstance(payload, dict):
        rate = payload.get("rate") or payload.get("rates", {}).get(quote)
        rate_date = payload.get("date")
        if rate is not None and rate_date:
            return Decimal(str(rate)), date.fromisoformat(rate_date)
    raise ValueError(f"No verified {base}/{quote} rate in provider response")


async def fetch_frankfurter_rate(base: str, quote: str) -> dict[str, Any]:
    settings = get_settings()
    base = base.upper()
    quote = quote.upper()
    url = f"{settings.frankfurter_base_url.rstrip('/')}/rates"
    async with httpx.AsyncClient(timeout=12) as client:
        response = await client.get(url, params={"base": base, "quotes": quote})
        response.raise_for_status()
        rate, rate_date = parse_frankfurter_response(response.json(), base, quote)
    return {"base_currency": base, "quote_currency": quote, "rate": rate, "rate_date": rate_date, "source": "Frankfurter v2"}
