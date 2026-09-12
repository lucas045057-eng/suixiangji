from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..models import Account, ExchangeRate, Transaction, User
from ..services.exchange import fetch_frankfurter_rate
from .domain import date_value, json_value, money
from .schemas import AccountIn, RateIn


def account_json(row: Account) -> dict:
    return json_value(
        {
            "id": row.id,
            "name": row.name,
            "type": row.kind,
            "kind": row.kind,
            "account_kind": row.account_kind,
            "currency": row.currency,
            "opening_balance": row.opening_balance,
            "opening_cny_amount": row.opening_cny_amount,
            "opening_exchange_rate": row.opening_exchange_rate,
            "opening_rate_date": row.opening_rate_date,
            "opening_rate_source": row.opening_rate_source,
            "is_liquid": row.is_liquid,
            "is_default_payment": row.is_default_payment,
            "deleted_at": row.deleted_at,
            "server_version": row.server_version,
            "updated_at": row.updated_at,
        }
    )


def save_account(
    db: Session,
    user: User,
    values: dict,
    *,
    deleted: bool = False,
    server_version: int | None = None,
) -> Account:
    name = str(values.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=422, detail="账户名称不能为空")
    duplicate = (
        db.query(Account)
        .filter(
            Account.user_id == user.id,
            Account.deleted_at.is_(None),
            Account.id != values["id"],
        )
        .all()
    )
    if any(row.name.strip().casefold() == name.casefold() for row in duplicate):
        raise HTTPException(status_code=409, detail="账户名称不能重复")
    currency = str(values.get("currency") or "CNY").upper()
    opening = Decimal(str(values.get("opening_balance", 0)))
    opening_cny = values.get("opening_cny_amount")
    if currency == "CNY":
        opening_cny = opening
    elif opening_cny is None:
        rate = (
            db.query(ExchangeRate)
            .filter(
                ExchangeRate.base_currency == currency,
                ExchangeRate.quote_currency == "CNY",
            )
            .order_by(ExchangeRate.rate_date.desc(), ExchangeRate.fetched_at.desc())
            .first()
        )
        if rate:
            opening_cny = money(opening * rate.rate)
            values = {
                **values,
                "opening_exchange_rate": rate.rate,
                "opening_rate_date": rate.rate_date,
                "opening_rate_source": rate.source,
            }
    row = db.get(Account, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    data = {
        "name": name,
        "kind": values.get("kind") or values.get("type") or "asset",
        "account_kind": values.get("account_kind") or "other",
        "currency": currency,
        "opening_balance": opening,
        "opening_cny_amount": (
            Decimal(str(opening_cny)) if opening_cny is not None else None
        ),
        "opening_exchange_rate": (
            Decimal(str(values["opening_exchange_rate"]))
            if values.get("opening_exchange_rate") is not None
            else None
        ),
        "opening_rate_date": (
            date_value(values["opening_rate_date"])
            if values.get("opening_rate_date")
            else None
        ),
        "opening_rate_source": values.get("opening_rate_source"),
        "is_liquid": bool(values.get("is_liquid", False)),
        "is_default_payment": bool(values.get("is_default_payment", False)),
    }
    if not row:
        row = Account(id=values["id"], user_id=user.id, **data)
        db.add(row)
    else:
        for key, value in data.items():
            setattr(row, key, value)
    row.deleted_at = datetime.now(timezone.utc) if deleted else None
    row.server_version = server_version if server_version is not None else row.server_version
    return row


def list_accounts(db: Session, user: User) -> dict:
    rows = (
        db.query(Account)
        .filter(Account.user_id == user.id, Account.deleted_at.is_(None))
        .all()
    )
    return {
        "items": [account_json(row) for row in rows],
        "server_version": user.sync_version,
    }


def create_account(db: Session, user: User, payload: AccountIn) -> dict:
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    user.sync_version += 1
    row = save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return account_json(row)


def update_account(
    db: Session,
    user: User,
    account_id: str,
    payload: AccountIn,
) -> dict:
    if payload.id and payload.id != account_id:
        raise HTTPException(status_code=422, detail="账户 ID 不一致")
    existing = db.get(Account, account_id)
    if not existing or existing.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    values = payload.model_dump()
    values["id"] = account_id
    user.sync_version += 1
    row = save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return account_json(row)


def delete_account(db: Session, user: User, account_id: str) -> dict:
    row = db.get(Account, account_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    user.sync_version += 1
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {
        "deleted": True,
        "id": account_id,
        "server_version": user.sync_version,
    }


def wealth(db: Session, user: User) -> dict:
    accounts = (
        db.query(Account)
        .filter(Account.user_id == user.id, Account.deleted_at.is_(None))
        .all()
    )
    rows = (
        db.query(Transaction)
        .filter(Transaction.user_id == user.id, Transaction.deleted_at.is_(None))
        .all()
    )
    details = []
    total_assets = Decimal("0")
    total_liabilities = Decimal("0")
    pending = 0
    for account in accounts:
        opening = (
            account.opening_cny_amount
            if account.currency != "CNY"
            else account.opening_balance
        )
        balance = opening or Decimal("0")
        account_pending = opening is None
        if account_pending:
            pending += 1
        for row in rows:
            if row.cny_amount is None:
                if (
                    row.account_id == account.id
                    or row.from_account_id == account.id
                    or row.to_account_id == account.id
                ):
                    pending += 1
                    account_pending = True
                continue
            value = row.cny_amount
            if row.kind == "transfer":
                if row.from_account_id == account.id:
                    balance -= value
                if row.to_account_id == account.id:
                    balance += value
            elif row.account_id == account.id:
                if account.kind == "liability":
                    balance += value if row.kind == "expense" else -value
                else:
                    balance += value if row.kind == "income" else -value
        detail = {
            **account_json(account),
            "cny_balance": money(balance),
            "conversion_status": "pending" if account_pending else "ready",
        }
        details.append(detail)
        if account.kind == "liability":
            total_liabilities += balance
        else:
            total_assets += balance
    return json_value(
        {
            "total_assets": money(total_assets),
            "total_liabilities": money(total_liabilities),
            "net_worth": money(total_assets - total_liabilities),
            "pending_conversion_count": pending,
            "accounts": details,
            "server_version": user.sync_version,
        }
    )


async def exchange_rate(
    db: Session,
    user: User,
    base: str,
    quote: str = "CNY",
) -> dict:
    base = base.upper().strip()
    quote = quote.upper().strip()
    if len(base) != 3 or len(quote) != 3 or base == quote:
        raise HTTPException(status_code=422, detail="请提供有效且不同的三位币种代码")
    try:
        values = await fetch_frankfurter_rate(base, quote)
    except Exception:
        raise HTTPException(status_code=502, detail="汇率服务暂不可用，请稍后再试") from None
    row = (
        db.query(ExchangeRate)
        .filter(
            ExchangeRate.base_currency == values["base_currency"],
            ExchangeRate.quote_currency == values["quote_currency"],
            ExchangeRate.rate_date == values["rate_date"],
            ExchangeRate.source == values["source"],
        )
        .first()
    )
    if row:
        row.rate = values["rate"]
        row.fetched_at = datetime.now(timezone.utc)
    else:
        row = ExchangeRate(**values)
        db.add(row)
    db.commit()
    return json_value(
        {
            "base_currency": row.base_currency,
            "quote_currency": row.quote_currency,
            "rate": row.rate,
            "rate_date": row.rate_date,
            "source": row.source,
            "updated_at": row.fetched_at,
        }
    )


def save_exchange_rate(db: Session, user: User, payload: RateIn) -> dict:
    raise HTTPException(
        status_code=403,
        detail="公共汇率仅由服务器可信来源更新，请请求获取汇率",
    )


# Compatibility names used by the aggregate API and scheduler.
_account_json = account_json
_save_account = save_account
_wealth = wealth
