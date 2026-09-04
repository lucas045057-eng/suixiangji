from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import or_
from sqlalchemy.orm import Session

from .config import get_settings
from .db import get_db
from .domain import TransactionRecord, calculate_cny, classify_natural_language, monthly_metrics, money, period_metrics
from .models import Account, AgentLog, Budget, Category, ExchangeRate, MonthlyReport, NetWorthSnapshot, SyncOperation, Transaction, User
from .schemas import AccountIn, BudgetIn, BudgetPatch, CategoryIn, CategoryPatch, DraftIn, LoginIn, PasswordChange, ProfilePatch, RateIn, RestoreIn, SyncPushIn, TransactionIn
from .security import create_token, decode_token, hash_password, verify_password
from .services.agent import configured_model, deterministic_report_text, make_draft
from .services.exchange import fetch_frankfurter_rate


router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def _user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        claims = decode_token(token)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="登录已失效") from exc
    found = db.get(User, claims.get("sub"))
    if not found:
        raise HTTPException(status_code=401, detail="用户不存在")
    token_version = claims.get("auth_version")
    if token_version is not None and int(token_version) != (found.auth_version or 0):
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    return found


def _profile_json(user: User, *, include_token: bool = False) -> dict:
    result = {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
        "quick_memories": user.quick_memories or [],
    }
    if include_token:
        result["access_token"] = create_token(user.id, user.username, user.auth_version or 0)
        result["token_type"] = "bearer"
    return result


def _date(value: str | date | None, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if value:
        return date.fromisoformat(value[:10])
    return fallback or date.today()


def _account_json(row: Account) -> dict:
    return _json_metrics({
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
    })


def _tx_json(row: Transaction) -> dict:
    return _json_metrics({
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


def _normalise_tx_payload(payload: dict, *, client_op_id: str | None = None, entity_id: str | None = None) -> dict:
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
        occurred_at = f"{_date(occurred).isoformat()}T00:00:00"
    elif isinstance(occurred_at, datetime):
        occurred_at = occurred_at.isoformat()
    if currency == "CNY" or (cny_amount is None and exchange_rate is not None):
        converted = calculate_cny(amount, currency, Decimal(str(exchange_rate)) if exchange_rate is not None else None, rate_date=_date(rate_date) if rate_date else None, source=rate_source)
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
        "exchange_rate_date": _date(rate_date) if rate_date else None,
        "exchange_rate_source": rate_source,
        "conversion_status": conversion_status,
        "category_id": payload.get("category_id"),
        "category_name": payload.get("category_name"),
        "account_id": payload.get("account_id"),
        "from_account_id": payload.get("from_account_id"),
        "to_account_id": payload.get("to_account_id"),
        "occurred_on": _date(occurred),
        "occurred_at": str(occurred_at),
        "note": payload.get("note") or "",
    }


def _attach_latest_rate(db: Session, values: dict) -> dict:
    currency = str(values.get("currency") or values.get("original_currency") or "CNY").upper()
    if currency == "CNY" or values.get("cny_amount") is not None or values.get("exchange_rate") is not None:
        return values
    rate = db.query(ExchangeRate).filter(ExchangeRate.base_currency == currency, ExchangeRate.quote_currency == "CNY").order_by(ExchangeRate.rate_date.desc(), ExchangeRate.fetched_at.desc()).first()
    if not rate:
        return values
    return {**values, "exchange_rate": rate.rate, "exchange_rate_date": rate.rate_date, "exchange_rate_source": rate.source}


def _save_tx(db: Session, user: User, values: dict, *, deleted: bool = False, server_version: int | None = None) -> Transaction:
    if values["kind"] != "transfer" and not values.get("account_id"):
        raise HTTPException(status_code=422, detail="非转账账目必须选择账户")
    for field in ("account_id", "from_account_id", "to_account_id"):
        account_id = values.get(field)
        if account_id and (not db.get(Account, account_id) or db.get(Account, account_id).user_id != user.id):
            raise HTTPException(status_code=422, detail=f"账户不存在: {account_id}")
    row = db.get(Transaction, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    if not row:
        row = Transaction(id=values["id"], user_id=user.id, **{key: value for key, value in values.items() if key != "id"})
        db.add(row)
    else:
        for key, value in values.items():
            if key != "id":
                setattr(row, key, value)
    row.deleted_at = datetime.now(timezone.utc) if deleted else None
    row.server_version = server_version if server_version is not None else row.server_version
    return row


def _save_account(db: Session, user: User, values: dict, *, deleted: bool = False, server_version: int | None = None) -> Account:
    name = str(values.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=422, detail="账户名称不能为空")
    duplicate = db.query(Account).filter(
        Account.user_id == user.id,
        Account.deleted_at.is_(None),
        Account.id != values["id"],
    ).all()
    if any(row.name.strip().casefold() == name.casefold() for row in duplicate):
        raise HTTPException(status_code=409, detail="账户名称不能重复")
    currency = str(values.get("currency") or "CNY").upper()
    opening = Decimal(str(values.get("opening_balance", 0)))
    opening_cny = values.get("opening_cny_amount")
    if currency == "CNY":
        opening_cny = opening
    elif opening_cny is None:
        rate = db.query(ExchangeRate).filter(ExchangeRate.base_currency == currency, ExchangeRate.quote_currency == "CNY").order_by(ExchangeRate.rate_date.desc(), ExchangeRate.fetched_at.desc()).first()
        if rate:
            opening_cny = money(opening * rate.rate)
            values = {**values, "opening_exchange_rate": rate.rate, "opening_rate_date": rate.rate_date, "opening_rate_source": rate.source}
    row = db.get(Account, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    data = {
        "name": name,
        "kind": values.get("kind") or values.get("type") or "asset",
        "account_kind": values.get("account_kind") or "other",
        "currency": currency,
        "opening_balance": opening,
        "opening_cny_amount": Decimal(str(opening_cny)) if opening_cny is not None else None,
        "opening_exchange_rate": Decimal(str(values["opening_exchange_rate"])) if values.get("opening_exchange_rate") is not None else None,
        "opening_rate_date": _date(values["opening_rate_date"]) if values.get("opening_rate_date") else None,
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


def _records(db: Session, user: User) -> list[TransactionRecord]:
    account_names = {row.id: row.name for row in db.query(Account).filter(Account.user_id == user.id).all()}
    return [
        TransactionRecord(
            row.id,
            row.kind,
            row.amount,
            row.currency,
            row.cny_amount,
            row.category_name,
            row.occurred_on,
            row.account_id,
            row.deleted_at is not None,
            row.occurred_at,
            account_names.get(row.account_id or ""),
        )
        for row in db.query(Transaction).filter(Transaction.user_id == user.id).all()
    ]


def _json_metrics(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_metrics(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_metrics(item) for item in value]
    return value


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "suixiangji-v1", "server_time": datetime.now(timezone.utc)}


@router.post("/auth/login")
def login(payload: LoginIn, db: Session = Depends(get_db)) -> dict:
    settings = get_settings()
    user = db.query(User).filter(User.username == payload.username).first()
    if user:
        if not verify_password(payload.password, user.password_hash):
            raise HTTPException(status_code=401, detail="用户名或密码错误")
    elif payload.username != settings.demo_username or payload.password != settings.demo_password:
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    if not user:
        user = User(id=str(uuid4()), username=payload.username, password_hash=hash_password(payload.password), display_name=payload.username)
        db.add(user)
        db.commit()
        for name, kind in (("餐饮", "expense"), ("交通", "expense"), ("住房", "expense"), ("工资", "income"), ("购物", "expense")):
            db.add(Category(id=str(uuid4()), user_id=user.id, name=name, kind=kind))
        db.commit()
    return {"access_token": create_token(user.id, user.username, user.auth_version or 0), "token_type": "bearer", "user_id": user.id, "username": user.username, "display_name": user.display_name or user.username}


@router.get("/auth/me")
def profile(user: User = Depends(_user)) -> dict:
    return _profile_json(user)


@router.patch("/auth/me")
def update_profile(payload: ProfilePatch, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    changed_credentials = False
    if payload.username is not None:
        username = payload.username.strip()
        if not username:
            raise HTTPException(status_code=422, detail="用户名不能为空")
        existing = db.query(User).filter(User.username == username, User.id != user.id).first()
        if existing:
            raise HTTPException(status_code=409, detail="用户名已存在")
        if username != user.username:
            user.username = username
            changed_credentials = True
    if payload.display_name is not None:
        user.display_name = payload.display_name.strip()
    if payload.quick_memories is not None:
        user.quick_memories = payload.quick_memories
    if changed_credentials:
        user.auth_version = (user.auth_version or 0) + 1
    db.commit()
    return _profile_json(user, include_token=True)


@router.post("/auth/password")
def change_password(payload: PasswordChange, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="当前密码错误")
    user.password_hash = hash_password(payload.new_password)
    user.auth_version = (user.auth_version or 0) + 1
    db.commit()
    return _profile_json(user, include_token=True)


@router.get("/accounts")
def list_accounts(db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    rows = db.query(Account).filter(Account.user_id == user.id, Account.deleted_at.is_(None)).all()
    return {"items": [_account_json(row) for row in rows], "server_version": user.sync_version}


@router.post("/accounts")
def create_account(payload: AccountIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    user.sync_version += 1
    row = _save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return _account_json(row)


@router.patch("/accounts/{account_id}")
def update_account(account_id: str, payload: AccountIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    if payload.id and payload.id != account_id:
        raise HTTPException(status_code=422, detail="账户 ID 不一致")
    if not db.get(Account, account_id) or db.get(Account, account_id).user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    user.sync_version += 1
    values = payload.model_dump()
    values["id"] = account_id
    row = _save_account(db, user, values, server_version=user.sync_version)
    db.commit()
    return _account_json(row)


@router.delete("/accounts/{account_id}")
def delete_account(account_id: str, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Account, account_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账户不存在")
    user.sync_version += 1
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {"deleted": True, "id": account_id, "server_version": user.sync_version}


@router.get("/categories")
def list_categories(db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    return {"items": [_category_json(row) for row in db.query(Category).filter(Category.user_id == user.id).all()], "server_version": user.sync_version}


def _category_json(row: Category) -> dict:
    return _json_metrics({"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind, "server_version": row.server_version, "updated_at": row.updated_at})


def _save_category(db: Session, user: User, values: dict, *, server_version: int | None = None, active: bool | None = None) -> Category:
    row = db.get(Category, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    if not row:
        row = Category(id=values["id"], user_id=user.id, name=values.get("name") or values["id"], kind=values.get("kind") or values.get("type") or "expense", active=True if active is None else active)
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


@router.post("/categories")
def create_category(payload: CategoryIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Category, payload.id) if payload.id else None
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    if not row:
        row = Category(id=payload.id or str(uuid4()), user_id=user.id, name=payload.name, kind=payload.kind, active=True)
        db.add(row)
    else:
        row.name = payload.name
        row.kind = payload.kind
        row.active = True
    user.sync_version += 1
    row.server_version = user.sync_version
    db.commit()
    return {"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind}


@router.patch("/categories/{category_id}")
def update_category(category_id: str, payload: CategoryPatch, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
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


@router.post("/categories/{category_id}/archive")
def archive_category(category_id: str, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Category, category_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="分类不存在")
    row.active = False
    user.sync_version += 1
    row.server_version = user.sync_version
    db.commit()
    return {"id": row.id, "name": row.name, "active": row.active, "type": row.kind, "kind": row.kind}


def _budget_json(row: Budget) -> dict:
    return _json_metrics({
        "id": row.id,
        "month": row.month,
        "category_id": row.category_id,
        "limit": row.limit,
        "active": row.active,
        "deleted_at": row.deleted_at,
        "server_version": row.server_version,
        "updated_at": row.updated_at,
    })


def _save_budget(db: Session, user: User, values: dict, *, server_version: int | None = None) -> Budget:
    row = db.get(Budget, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    data = {
        "month": values["month"],
        "category_id": values["category_id"],
        "limit": Decimal(str(values["limit"])),
        "active": bool(values.get("active", True)),
    }
    if not row:
        row = Budget(id=values["id"], user_id=user.id, **data)
        db.add(row)
    else:
        for key, value in data.items():
            setattr(row, key, value)
        row.deleted_at = None
    row.server_version = server_version if server_version is not None else row.server_version
    return row


@router.get("/budgets")
def list_budgets(month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"), db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    query = db.query(Budget).filter(Budget.user_id == user.id, Budget.deleted_at.is_(None), Budget.active.is_(True))
    if month:
        query = query.filter(Budget.month == month)
    rows = query.order_by(Budget.month.desc(), Budget.updated_at.desc()).all()
    return {"items": [_budget_json(row) for row in rows], "server_version": user.sync_version}


@router.post("/budgets")
def create_budget(payload: BudgetIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    existing = db.query(Budget).filter(Budget.user_id == user.id, Budget.month == values["month"], Budget.category_id == values["category_id"], Budget.deleted_at.is_(None)).first()
    if existing and not payload.id:
        values["id"] = existing.id
    user.sync_version += 1
    row = _save_budget(db, user, values, server_version=user.sync_version)
    db.commit()
    return _budget_json(row)


@router.patch("/budgets/{budget_id}")
def update_budget(budget_id: str, payload: BudgetPatch, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Budget, budget_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    values = payload.model_dump(exclude_unset=True)
    values = {**_budget_json(row), **values, "id": budget_id}
    user.sync_version += 1
    row = _save_budget(db, user, values, server_version=user.sync_version)
    db.commit()
    return _budget_json(row)


@router.delete("/budgets/{budget_id}")
def delete_budget(budget_id: str, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Budget, budget_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    user.sync_version += 1
    row.active = False
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {"deleted": True, "id": budget_id, "server_version": user.sync_version}


@router.get("/transactions")
def list_transactions(db: Session = Depends(get_db), user: User = Depends(_user), include_deleted: bool = False) -> dict:
    query = db.query(Transaction).filter(Transaction.user_id == user.id)
    if not include_deleted:
        query = query.filter(Transaction.deleted_at.is_(None))
    return {"items": [_tx_json(row) for row in query.order_by(Transaction.occurred_on.desc()).all()], "server_version": user.sync_version}


@router.post("/transactions")
def create_transaction(payload: TransactionIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    existing = db.query(Transaction).filter(Transaction.user_id == user.id, Transaction.client_op_id == payload.client_op_id).first()
    if existing:
        return _tx_json(existing)
    user.sync_version += 1
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    row = _save_tx(db, user, _normalise_tx_payload(_attach_latest_rate(db, values)), server_version=user.sync_version)
    db.add(SyncOperation(user_id=user.id, client_op_id=row.client_op_id, entity="transactions", entity_id=row.id, server_version=user.sync_version))
    db.commit()
    return _tx_json(row)


@router.patch("/transactions/{transaction_id}")
def update_transaction(transaction_id: str, payload: TransactionIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    if transaction_id != payload.id and payload.id:
        raise HTTPException(status_code=422, detail="账目 ID 不一致")
    existing = db.get(Transaction, transaction_id)
    if not existing or existing.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    user.sync_version += 1
    values = _normalise_tx_payload(_attach_latest_rate(db, payload.model_dump()), entity_id=transaction_id)
    row = _save_tx(db, user, values, server_version=user.sync_version)
    db.commit()
    return _tx_json(row)


@router.delete("/transactions/{transaction_id}")
def delete_transaction(transaction_id: str, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    row = db.get(Transaction, transaction_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="账目不存在")
    user.sync_version += 1
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {"deleted": True, "id": transaction_id, "server_version": user.sync_version}


@router.post("/agent/draft")
async def agent_draft(payload: DraftIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    draft, meta = await make_draft(payload.text)
    if draft.get("account_hint"):
        account = db.query(Account).filter(Account.user_id == user.id, Account.name == draft["account_hint"], Account.deleted_at.is_(None)).first()
        if account:
            draft["account_id"] = account.id
    if draft.get("category_hint"):
        category = db.query(Category).filter(Category.user_id == user.id, Category.name == draft["category_hint"]).first()
        if category:
            draft["category_id"] = category.id
    db.add(AgentLog(user_id=user.id, task="draft", model=meta.get("model"), status=meta.get("status", "unknown"), input_tokens=meta.get("input_tokens"), output_tokens=meta.get("output_tokens"), result_summary=meta.get("result_summary") or "rules-first draft"))
    db.commit()
    return _json_metrics({**draft, "type": draft["kind"], "date": draft["occurred_on"], "account_name": draft.get("account_hint"), "category_name": draft.get("category_hint"), "currency": draft.get("currency", "CNY")})


@router.get("/stats")
def stats(
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    period: Literal["day", "week", "month", "custom"] | None = Query(default=None),
    start: str | None = Query(default=None),
    end: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(_user),
) -> dict:
    rows = _records(db, user)
    if period is None:
        if month is None:
            raise HTTPException(status_code=422, detail="month 或 period 必须提供")
        year, month_number = map(int, month.split("-"))
        range_start = date(year, month_number, 1)
        range_end = date(year + (month_number == 12), 1 if month_number == 12 else month_number + 1, 1) - timedelta(days=1)
        current = monthly_metrics(rows, month)
        aggregate = period_metrics(rows, "month", range_start, range_end)
        previous = f"{year - 1:04d}-12" if month_number == 1 else f"{year:04d}-{month_number - 1:02d}"
        prior = monthly_metrics(rows, previous)
        current.update(aggregate)
        current["previous"] = prior
        current["expense_change"] = current["expense"] - prior["expense"]
        return _json_metrics(current)

    if start is None:
        raise HTTPException(status_code=422, detail="period 统计必须提供 start")
    range_start = _date(start)
    if end is not None:
        range_end = _date(end)
    elif period == "day":
        range_end = range_start
    elif period == "week":
        range_end = range_start + timedelta(days=6)
    elif period == "month":
        range_end = date(range_start.year + (range_start.month == 12), 1 if range_start.month == 12 else range_start.month + 1, 1) - timedelta(days=1)
    else:
        range_end = range_start
    aggregate = period_metrics(rows, period, range_start, range_end)
    return _json_metrics({
        "month": month or f"{range_start.year:04d}-{range_start.month:02d}",
        "income": aggregate["income_total"],
        "expense": aggregate["expense_total"],
        "balance": aggregate["net_worth_change"],
        "savings_rate": money(aggregate["net_worth_change"] / aggregate["income_total"] * 100) if aggregate["income_total"] else Decimal("0"),
        "category_totals": aggregate["expense_by_category"],
        "data_sufficient": bool(rows) and aggregate["pending_conversion_count"] == 0,
        **aggregate,
    })


def _wealth(db: Session, user: User) -> dict:
    accounts = db.query(Account).filter(Account.user_id == user.id, Account.deleted_at.is_(None)).all()
    rows = db.query(Transaction).filter(Transaction.user_id == user.id, Transaction.deleted_at.is_(None)).all()
    details = []
    total_assets = Decimal("0")
    total_liabilities = Decimal("0")
    pending = 0
    for account in accounts:
        opening = account.opening_cny_amount if account.currency != "CNY" else account.opening_balance
        balance = opening or Decimal("0")
        account_pending = opening is None
        if account_pending:
            pending += 1
        for row in rows:
            if row.cny_amount is None:
                if row.account_id == account.id or row.from_account_id == account.id or row.to_account_id == account.id:
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
        detail = {**_account_json(account), "cny_balance": money(balance), "conversion_status": "pending" if account_pending else "ready"}
        details.append(detail)
        if account.kind == "liability":
            total_liabilities += balance
        else:
            total_assets += balance
    return _json_metrics({"total_assets": money(total_assets), "total_liabilities": money(total_liabilities), "net_worth": money(total_assets - total_liabilities), "pending_conversion_count": pending, "accounts": details, "server_version": user.sync_version})


@router.get("/wealth")
def wealth(db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    return _wealth(db, user)


@router.get("/exchange/rates")
async def exchange_rate(base: str, quote: str = "CNY", db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    base = base.upper().strip()
    quote = quote.upper().strip()
    if len(base) != 3 or len(quote) != 3 or base == quote:
        raise HTTPException(status_code=422, detail="请提供有效且不同的三位币种代码")
    try:
        values = await fetch_frankfurter_rate(base, quote)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"汇率服务不可用，未写入猜测值: {exc}") from exc
    row = db.query(ExchangeRate).filter(ExchangeRate.base_currency == values["base_currency"], ExchangeRate.quote_currency == values["quote_currency"], ExchangeRate.rate_date == values["rate_date"], ExchangeRate.source == values["source"]).first()
    if row:
        row.rate = values["rate"]
        row.fetched_at = datetime.now(timezone.utc)
    else:
        row = ExchangeRate(**values)
        db.add(row)
    db.commit()
    return _json_metrics({"base_currency": row.base_currency, "quote_currency": row.quote_currency, "rate": row.rate, "rate_date": row.rate_date, "source": row.source, "updated_at": row.fetched_at})


@router.post("/exchange/rates")
def save_exchange_rate(payload: RateIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    values = payload.model_dump()
    values["base_currency"] = values["base_currency"].upper().strip()
    values["quote_currency"] = values["quote_currency"].upper().strip()
    if len(values["base_currency"]) != 3 or len(values["quote_currency"]) != 3 or values["base_currency"] == values["quote_currency"]:
        raise HTTPException(status_code=422, detail="请提供有效且不同的三位币种代码")
    row = db.query(ExchangeRate).filter(ExchangeRate.base_currency == values["base_currency"], ExchangeRate.quote_currency == values["quote_currency"], ExchangeRate.rate_date == values["rate_date"], ExchangeRate.source == values["source"]).first()
    if row:
        row.rate = values["rate"]
        row.fetched_at = datetime.now(timezone.utc)
    else:
        row = ExchangeRate(**values)
        db.add(row)
    db.commit()
    return _json_metrics({"base_currency": row.base_currency, "quote_currency": row.quote_currency, "rate": row.rate, "rate_date": row.rate_date, "source": row.source, "updated_at": row.fetched_at})


@router.get("/reports/monthly/{month}")
async def monthly_report(month: str, force: bool = False, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    existing = db.query(MonthlyReport).filter(MonthlyReport.user_id == user.id, MonthlyReport.month == month).first()
    if existing and not force:
        return {"id": existing.id, "month": existing.month, "metrics": existing.metrics, "summary": existing.narrative, "ai_status": existing.ai_status, "generated_at": existing.created_at}
    metrics = stats(month=month, period=None, start=None, end=None, db=db, user=user)
    prior_report = db.query(MonthlyReport).filter(MonthlyReport.user_id == user.id, MonthlyReport.month != month).order_by(MonthlyReport.month.desc()).first()
    narrative = deterministic_report_text(metrics, prior_report.metrics if prior_report else None)
    ai_status = "unavailable"
    model = configured_model()
    if get_settings().llm_provider.lower() not in ("", "none", "disabled"):
        try:
            narrative, meta = await model.complete("monthly_report", {"month": month, "metrics": metrics})
            ai_status = "success"
            db.add(AgentLog(user_id=user.id, task="monthly_report", model=meta.get("model"), status="success", input_tokens=meta.get("input_tokens"), output_tokens=meta.get("output_tokens"), result_summary="structured metrics only"))
        except Exception as exc:
            db.add(AgentLog(user_id=user.id, task="monthly_report", model=get_settings().llm_model or None, status="unavailable", result_summary=str(exc)))
    stored_metrics = _json_metrics(metrics)
    if existing:
        existing.metrics = stored_metrics
        existing.narrative = narrative
        existing.ai_status = ai_status
        row = existing
    else:
        row = MonthlyReport(user_id=user.id, month=month, metrics=stored_metrics, narrative=narrative, ai_status=ai_status)
        db.add(row)
    wealth_data = _wealth(db, user)
    snapshot = db.query(NetWorthSnapshot).filter(NetWorthSnapshot.user_id == user.id, NetWorthSnapshot.month == month).first()
    snapshot_data = {"total_assets_cny": wealth_data["total_assets"], "total_liabilities_cny": wealth_data["total_liabilities"], "net_worth_cny": wealth_data["net_worth"], "pending_conversion_count": wealth_data["pending_conversion_count"]}
    if not snapshot:
        # A month's snapshot is immutable once written, so later exchange-rate refreshes cannot rewrite history.
        db.add(NetWorthSnapshot(user_id=user.id, month=month, **snapshot_data))
    db.commit()
    return {"id": row.id, "month": month, "metrics": metrics, "summary": narrative, "ai_status": ai_status, "generated_at": row.created_at}


@router.post("/sync/push")
def sync_push(payload: SyncPushIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    accepted = []
    conflicts = []
    for operation in payload.operations:
        previous = db.query(SyncOperation).filter(SyncOperation.user_id == user.id, SyncOperation.client_op_id == operation.client_op_id).first()
        if previous:
            accepted.append({"client_op_id": operation.client_op_id, "entity_id": previous.entity_id, "server_version": previous.server_version, "created": False})
            continue
        raw_version = operation.payload.get("server_version")
        existing = {
            "transactions": db.get(Transaction, operation.entity_id),
            "accounts": db.get(Account, operation.entity_id),
            "categories": db.get(Category, operation.entity_id),
            "budgets": db.get(Budget, operation.entity_id),
        }[operation.entity]
        if existing and existing.user_id == user.id and raw_version is not None and int(raw_version) < existing.server_version:
            conflicts.append({"client_op_id": operation.client_op_id, "entity_id": operation.entity_id, "reason": "server has a newer version"})
            continue
        user.sync_version += 1
        if operation.entity == "transactions":
            row = _save_tx(db, user, _normalise_tx_payload(_attach_latest_rate(db, operation.payload), client_op_id=operation.client_op_id, entity_id=operation.entity_id), deleted=operation.type == "delete", server_version=user.sync_version)
        elif operation.entity == "accounts":
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            data.setdefault("name", operation.entity_id)
            row = _save_account(db, user, data, deleted=operation.type == "delete", server_version=user.sync_version)
        elif operation.entity == "categories":
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            row = _save_category(db, user, data, server_version=user.sync_version, active=operation.type != "delete")
        else:
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            data.setdefault("month", datetime.now(timezone.utc).strftime("%Y-%m"))
            data.setdefault("category_id", "other")
            data.setdefault("limit", 0.01)
            row = _save_budget(db, user, data, server_version=user.sync_version)
        db.add(SyncOperation(user_id=user.id, client_op_id=operation.client_op_id, entity=operation.entity, entity_id=operation.entity_id, server_version=user.sync_version))
        accepted.append({"client_op_id": operation.client_op_id, "entity_id": operation.entity_id, "server_version": user.sync_version, "created": True})
    db.commit()
    return {"accepted": accepted, "conflicts": conflicts, "server_version": user.sync_version}


@router.get("/sync/pull")
def sync_pull(since_version: int = 0, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    transactions = db.query(Transaction).filter(Transaction.user_id == user.id, Transaction.server_version > since_version).order_by(Transaction.server_version.asc()).all()
    accounts = db.query(Account).filter(Account.user_id == user.id, Account.server_version > since_version).order_by(Account.server_version.asc()).all()
    categories = db.query(Category).filter(Category.user_id == user.id, Category.server_version > since_version).order_by(Category.server_version.asc()).all()
    budgets = db.query(Budget).filter(Budget.user_id == user.id, Budget.server_version > since_version).order_by(Budget.server_version.asc()).all()
    return {"items": [_tx_json(row) for row in transactions], "transactions": [_tx_json(row) for row in transactions], "accounts": [_account_json(row) for row in accounts], "categories": [_category_json(row) for row in categories], "budgets": [_budget_json(row) for row in budgets], "server_version": user.sync_version}


@router.get("/backup/export")
def backup_export(db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    accounts = db.query(Account).filter(Account.user_id == user.id).all()
    transactions = db.query(Transaction).filter(Transaction.user_id == user.id).all()
    return {"schema_version": 1, "exported_at": datetime.now(timezone.utc), "accounts": [_account_json(row) for row in accounts], "transactions": [_tx_json(row) for row in transactions]}


@router.post("/backup/restore")
def backup_restore(payload: RestoreIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    imported_accounts = 0
    imported_transactions = 0
    for item in payload.accounts:
        data = dict(item)
        data["id"] = data.get("id") or str(uuid4())
        data.setdefault("name", data["id"])
        _save_account(db, user, data)
        imported_accounts += 1
    for item in payload.transactions:
        data = _normalise_tx_payload(_attach_latest_rate(db, dict(item)))
        _save_tx(db, user, data, deleted=bool(item.get("deleted_at")))
        imported_transactions += 1
    db.commit()
    return {"restored": True, "accounts": imported_accounts, "transactions": imported_transactions}
