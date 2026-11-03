from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import uuid4

from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy.orm import Session

from ..models import Account, ExchangeRate, Transaction, User
from ..services.exchange import fetch_frankfurter_rate
from .domain import date_value, json_value, money, cny_value
from .schemas import AccountIn, AccountPatch, RateIn
from .names import normalize_account_name
from .replay import account_balance
from ..core.financial_lock import lock_current_user


def account_json(row: Account) -> dict:
    return json_value(
        {
            "id": row.id,
            "name": row.name,
            "note": row.note,
            "archived_at": row.archived_at,
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
) -> Account | None:
    row = db.get(Account, values["id"], populate_existing=True)
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    if deleted:
        if row is not None:
            row.deleted_at = datetime.now(timezone.utc)
            row.server_version = server_version if server_version is not None else row.server_version
        return row

    creating = row is None
    # Schema defaults belong only to creation; a patch must retain absent fields.
    supplied = {k: v for k, v in values.items() if k in AccountIn.model_fields}
    supplied.pop("id", None)
    if "kind" not in supplied and "type" in values:
        supplied["kind"] = values["type"]
    if "name" in supplied:
        supplied["name"] = str(supplied["name"] or "").strip()
    if "note" in supplied:
        supplied["note"] = str(supplied["note"] or "").strip()
    raw_archived = supplied.get("archived_at")
    if raw_archived is not None and not isinstance(raw_archived, (str, datetime)):
        raise HTTPException(status_code=422, detail="归档时间无效")
    try:
        schema = AccountIn if creating else AccountPatch
        data = schema(**supplied).model_dump(exclude_unset=not creating)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from None
    data.pop("id", None)
    name = data.get("name", row.name if row else "")
    if not name:
        raise HTTPException(status_code=422, detail="账户名称不能为空")
    normalized = normalize_account_name(name)
    # Tombstones restored from backup do not occupy a live name.
    if (row is None or row.deleted_at is None) and not values.get("deleted_at"):
        duplicate = db.query(Account).filter(
            Account.user_id == user.id, Account.deleted_at.is_(None),
            Account.id != values["id"], Account.normalized_name == normalized,
        ).first()
        if duplicate:
            raise HTTPException(status_code=409, detail="账户名称不能重复")
    if creating or "name" in data:
        data["normalized_name"] = normalized
    currency = str(data.get("currency", row.currency if row else "CNY")).upper()
    if creating or "currency" in data:
        data["currency"] = currency
    opening = data.get("opening_balance", row.opening_balance if row else Decimal(0))
    if currency == "CNY" and creating:
        data["opening_cny_amount"] = opening
    elif creating and data.get("opening_cny_amount") is None:
        rate = db.query(ExchangeRate).filter(
            ExchangeRate.base_currency == currency, ExchangeRate.quote_currency == "CNY",
        ).order_by(ExchangeRate.rate_date.desc(), ExchangeRate.fetched_at.desc()).first()
        if rate:
            data.update(opening_cny_amount=money(opening * rate.rate),
                        opening_exchange_rate=rate.rate, opening_rate_date=rate.rate_date,
                        opening_rate_source=rate.source)
    if creating:
        row = Account(id=values["id"], user_id=user.id, **data)
        db.add(row)
    else:
        for key, value in data.items():
            setattr(row, key, value)
    # An ordinary upsert cannot resurrect a tombstone.
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
    user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
    values = payload.model_dump(exclude_unset=True)
    values["id"] = values.get("id") or str(uuid4())
    user.sync_version += 1
    row = save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return account_json(row)


def update_account(
    db: Session,
    user: User,
    account_id: str,
    payload: AccountPatch,
) -> dict:
    user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
    if payload.id and payload.id != account_id:
        raise HTTPException(status_code=422, detail="账户 ID 不一致")
    existing = db.get(Account, account_id)
    if not existing or existing.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    values = payload.model_dump(exclude_unset=True)
    values["id"] = account_id
    user.sync_version += 1
    row = save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return account_json(row)


def delete_account(db: Session, user: User, account_id: str) -> dict:
    user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
    row = db.get(Account, account_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    user.sync_version += 1
    save_account(db, user, {"id": account_id}, deleted=True, server_version=user.sync_version)
    db.commit()
    return {
        "deleted": True,
        "id": account_id,
        "server_version": user.sync_version,
    }


def wealth(db: Session, user: User, *, as_of_date: date | None = None, include_adjustments: bool = False) -> dict:
    accounts = (
        db.query(Account)
        .filter(Account.user_id == user.id, Account.deleted_at.is_(None), Account.archived_at.is_(None))
        .all()
    )
    query = db.query(Transaction).filter(Transaction.user_id == user.id, Transaction.deleted_at.is_(None))
    if as_of_date is not None:
        query = query.filter(Transaction.occurred_on <= as_of_date)
    if not include_adjustments:
        query = query.filter(Transaction.kind != "adjustment")
    rows = query.all()
    details = []
    total_assets = Decimal("0")
    total_liabilities = Decimal("0")
    pending = 0
    for account in accounts:
        balance, account_pending_count = account_balance(account, rows, include_adjustments=include_adjustments)
        account_pending = account_pending_count > 0
        pending += account_pending_count
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
        cached = (db.query(ExchangeRate).filter(
            ExchangeRate.base_currency == base, ExchangeRate.quote_currency == quote,
            ExchangeRate.rate > 0).order_by(ExchangeRate.rate_date.desc(),
            ExchangeRate.fetched_at.desc()).first())
        if cached is not None:
            return json_value(dict(base_currency=base,quote_currency=quote,
                rate=cached.rate,rate_date=cached.rate_date,source=cached.source,
                updated_at=cached.fetched_at,stale=True))
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
            "stale": False,
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
