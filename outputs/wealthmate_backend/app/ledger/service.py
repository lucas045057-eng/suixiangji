from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..assets.domain import money
from ..models import Account, Category, ExchangeRate, SyncOperation, Transaction, User
from .domain import date_value, json_metrics, normalise_transaction_payload
from .schemas import CategoryIn, CategoryPatch, TransactionIn


def transaction_json(row: Transaction) -> dict:
    return json_metrics({
        "id": row.id,
        "date": row.occurred_on,
        "occurred_on": row.occurred_on,
        "type": row.kind,
        "kind": row.kind,
        "amount": row.amount,
        "currency": row.currency,
        "original_amount": row.amount,
        "original_currency": row.currency,
        "cny_amount": row.cny_amount,
        "exchange_rate": row.exchange_rate,
        "exchange_rate_date": row.exchange_rate_date,
        "exchange_rate_source": row.exchange_rate_source,
        "conversion_status": row.conversion_status,
        "category_id": row.category_id,
        "category_name": row.category_name,
        "account_id": row.account_id,
        "from_account_id": row.from_account_id,
        "to_account_id": row.to_account_id,
        "occurred_at": row.occurred_at or f"{row.occurred_on.isoformat()}T00:00:00",
        "note": row.note,
        "client_op_id": row.client_op_id,
        "deleted_at": row.deleted_at,
        "server_version": row.server_version,
        "updated_at": row.updated_at,
    })


def category_json(row: Category) -> dict:
    return json_metrics({
        "id": row.id,
        "name": row.name,
        "active": row.active,
        "type": row.kind,
        "kind": row.kind,
        "server_version": row.server_version,
        "updated_at": row.updated_at,
    })


def attach_latest_rate(db: Session, values: dict) -> dict:
    currency = str(values.get("currency") or values.get("original_currency") or "CNY").upper()
    if currency == "CNY" or values.get("cny_amount") is not None or values.get("exchange_rate") is not None:
        return values
    rate = db.query(ExchangeRate).filter(
        ExchangeRate.base_currency == currency,
        ExchangeRate.quote_currency == "CNY",
    ).order_by(ExchangeRate.rate_date.desc(), ExchangeRate.fetched_at.desc()).first()
    if not rate:
        return values
    return {
        **values,
        "exchange_rate": rate.rate,
        "exchange_rate_date": rate.rate_date,
        "exchange_rate_source": rate.source,
    }


def save_transaction(
    db: Session,
    user: User,
    values: dict,
    *,
    deleted: bool = False,
    server_version: int | None = None,
) -> Transaction:
    if values["kind"] != "transfer" and not values.get("account_id"):
        raise HTTPException(status_code=422, detail="非转账账目必须选择账户")
    row = db.get(Transaction, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    for field in ("account_id", "from_account_id", "to_account_id"):
        account_id = values.get(field)
        if account_id:
            account = db.get(Account, account_id)
            if not account or account.user_id != user.id:
                raise HTTPException(status_code=422, detail=f"账户不存在: {account_id}")
    category_id = values.get("category_id")
    if category_id:
        category = db.get(Category, category_id)
        if not category or category.user_id != user.id:
            raise HTTPException(status_code=422, detail=f"分类不存在: {category_id}")
        if values["kind"] != "transfer" and category.kind != values["kind"]:
            raise HTTPException(status_code=422, detail="分类类型与账目类型不一致")
    if not row:
        row = Transaction(
            id=values["id"],
            user_id=user.id,
            **{key: value for key, value in values.items() if key != "id"},
        )
        db.add(row)
    else:
        for key, value in values.items():
            if key != "id":
                setattr(row, key, value)
    row.deleted_at = datetime.now(timezone.utc) if deleted else None
    row.server_version = server_version if server_version is not None else row.server_version
    return row


def save_category(
    db: Session,
    user: User,
    values: dict,
    *,
    server_version: int | None = None,
    active: bool | None = None,
) -> Category:
    row = db.get(Category, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    if not row:
        row = Category(
            id=values["id"],
            user_id=user.id,
            name=values.get("name") or values["id"],
            kind=values.get("kind") or values.get("type") or "expense",
            active=True if active is None else active,
        )
        db.add(row)
    else:
        if values.get("name") is not None:
            row.name = values["name"]
        if values.get("kind") or values.get("type"):
            row.kind = values.get("kind") or values.get("type")
        if active is not None:
            row.active = active
    row.server_version = server_version if server_version is not None else row.server_version
    return row


def list_categories(db: Session, user: User) -> dict:
    rows = db.query(Category).filter(Category.user_id == user.id).all()
    return {"items": [category_json(row) for row in rows], "server_version": user.sync_version}


def create_category(db: Session, user: User, payload: CategoryIn) -> dict:
    row = db.get(Category, payload.id) if payload.id else None
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    if not row:
        row = Category(
            id=payload.id or str(uuid4()),
            user_id=user.id,
            name=payload.name,
            kind=payload.kind,
            active=True,
        )
        db.add(row)
    else:
        row.name = payload.name
        row.kind = payload.kind
        row.active = True
    user.sync_version += 1
    row.server_version = user.sync_version
    db.commit()
    return {"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind}


def update_category(
    db: Session,
    user: User,
    category_id: str,
    payload: CategoryPatch,
) -> dict:
    row = db.get(Category, category_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    values = payload.model_dump(exclude_unset=True)
    if "name" in values:
        row.name = values["name"]
    if "active" in values:
        row.active = values["active"]
    user.sync_version += 1
    row.server_version = user.sync_version
    db.commit()
    return {"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind}


def archive_category(db: Session, user: User, category_id: str) -> dict:
    row = db.get(Category, category_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    row.active = False
    user.sync_version += 1
    row.server_version = user.sync_version
    db.commit()
    return {"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind}


def list_transactions(db: Session, user: User, include_deleted: bool = False) -> dict:
    query = db.query(Transaction).filter(Transaction.user_id == user.id)
    if not include_deleted:
        query = query.filter(Transaction.deleted_at.is_(None))
    rows = query.order_by(Transaction.occurred_on.desc()).all()
    return {"items": [transaction_json(row) for row in rows], "server_version": user.sync_version}


def create_transaction(db: Session, user: User, payload: TransactionIn) -> dict:
    existing = db.query(Transaction).filter(
        Transaction.user_id == user.id,
        Transaction.client_op_id == payload.client_op_id,
    ).first()
    if existing:
        return transaction_json(existing)
    user.sync_version += 1
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    row = save_transaction(
        db,
        user,
        normalise_transaction_payload(attach_latest_rate(db, values)),
        server_version=user.sync_version,
    )
    db.add(SyncOperation(
        user_id=user.id,
        client_op_id=row.client_op_id,
        entity="transactions",
        entity_id=row.id,
        server_version=user.sync_version,
    ))
    db.commit()
    return transaction_json(row)


def update_transaction(
    db: Session,
    user: User,
    transaction_id: str,
    payload: TransactionIn,
) -> dict:
    if transaction_id != payload.id and payload.id:
        raise HTTPException(status_code=422, detail="账目 ID 不一致")
    existing = db.get(Transaction, transaction_id)
    if not existing or existing.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    user.sync_version += 1
    values = normalise_transaction_payload(
        attach_latest_rate(db, payload.model_dump()),
        entity_id=transaction_id,
    )
    row = save_transaction(db, user, values, server_version=user.sync_version)
    db.commit()
    return transaction_json(row)


def delete_transaction(db: Session, user: User, transaction_id: str) -> dict:
    row = db.get(Transaction, transaction_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    user.sync_version += 1
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {"deleted": True, "id": transaction_id, "server_version": user.sync_version}


# Compatibility names used by the aggregate API and its sync pipeline.
_tx_json = transaction_json
_category_json = category_json
_attach_latest_rate = attach_latest_rate
_normalise_tx_payload = normalise_transaction_payload
_save_tx = save_transaction
_save_category = save_category
