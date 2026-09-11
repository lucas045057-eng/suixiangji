from datetime import date, datetime
from decimal import Decimal
from uuid import uuid4

from ..domain import calculate_cny


def date_value(value: str | date | None, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if value:
        return date.fromisoformat(value[:10])
    return fallback or date.today()


def json_metrics(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: json_metrics(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_metrics(item) for item in value]
    return value


def normalise_transaction_payload(
    payload: dict,
    *,
    client_op_id: str | None = None,
    entity_id: str | None = None,
) -> dict:
    kind = payload.get("kind") or payload.get("type") or "expense"
    occurred = payload.get("occurred_on") or payload.get("date") or date.today().isoformat()
    amount = Decimal(str(payload.get("amount", payload.get("original_amount", 0))))
    currency = str(payload.get("currency") or payload.get("original_currency") or "CNY").upper()
    exchange_rate = payload.get("exchange_rate")
    rate_date = payload.get("exchange_rate_date")
    rate_source = payload.get("exchange_rate_source")
    cny_amount = payload.get("cny_amount")
    occurred_at = payload.get("occurred_at")
    if occurred_at is None:
        occurred_at = f"{date_value(occurred).isoformat()}T00:00:00"
    elif isinstance(occurred_at, datetime):
        occurred_at = occurred_at.isoformat()
    if currency == "CNY" or (cny_amount is None and exchange_rate is not None):
        converted = calculate_cny(
            amount,
            currency,
            Decimal(str(exchange_rate)) if exchange_rate is not None else None,
            rate_date=date_value(rate_date) if rate_date else None,
            source=rate_source,
        )
        cny_amount = converted["cny_amount"]
        exchange_rate = converted["exchange_rate"]
        rate_date = converted["exchange_rate_date"]
        rate_source = converted["exchange_rate_source"]
        conversion_status = converted["conversion_status"]
    else:
        conversion_status = "ready" if cny_amount is not None else "pending"
    return {
        "id": payload.get("id") or entity_id or str(uuid4()),
        "client_op_id": payload.get("client_op_id") or client_op_id or str(uuid4()),
        "kind": kind,
        "amount": amount,
        "currency": currency,
        "cny_amount": Decimal(str(cny_amount)) if cny_amount is not None else None,
        "exchange_rate": Decimal(str(exchange_rate)) if exchange_rate is not None else None,
        "exchange_rate_date": date_value(rate_date) if rate_date else None,
        "exchange_rate_source": rate_source,
        "conversion_status": conversion_status,
        "category_id": payload.get("category_id"),
        "category_name": payload.get("category_name"),
        "account_id": payload.get("account_id"),
        "from_account_id": payload.get("from_account_id"),
        "to_account_id": payload.get("to_account_id"),
        "occurred_on": date_value(occurred),
        "occurred_at": str(occurred_at),
        "note": payload.get("note") or "",
    }
