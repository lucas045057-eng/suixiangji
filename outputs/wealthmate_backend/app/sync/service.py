from __future__ import annotations

from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..assets.service import account_json as _account_json
from ..assets.service import save_account as _save_account
from ..budget.service import budget_json as _budget_json
from ..budget.service import save_budget as _save_budget
from ..budget.service import budget_with_same_key
from ..ledger.service import _attach_latest_rate
from ..ledger.service import _category_json
from ..ledger.service import _normalise_tx_payload
from ..ledger.service import _save_category
from ..ledger.service import _save_tx
from ..ledger.service import _tx_json
from ..core.financial_lock import lock_current_user as _lock_current_user
from ..core.protocol import enforce_sync_floor
from .v1_accounts import normalize_v1_account
from ..models import Account, Budget, Category, SyncOperation, Transaction, User
from .conflict import has_newer_server_version
from .ordering import order_operations
from .schemas import SyncPushIn


def _current_entity(db: Session, entity: str, entity_id: str, user_id: str):
    model = {
        "transactions": Transaction,
        "accounts": Account,
        "categories": Category,
        "budgets": Budget,
    }[entity]
    return db.execute(
        select(model)
        .where(model.id == entity_id, model.user_id == user_id)
        .execution_options(populate_existing=True)
    ).scalar_one_or_none()


def push(payload: SyncPushIn, db: Session, user: User) -> dict:
    verified_auth_version = user.auth_version or 0
    accepted = []
    conflicts = []
    ordered_operations = order_operations(payload.operations)
    transaction_started = db.in_transaction()
    if not transaction_started:
        db.begin()
    try:
        locked_user = _lock_current_user(db, user.id)
        if (locked_user.auth_version or 0) != verified_auth_version:
            raise HTTPException(status_code=401, detail='登录已失效，请重新登录')
        enforce_sync_floor(locked_user, 1)
        for operation in ordered_operations:
            # The lookup happens after the User lock, so a retry that waited
            # behind another push observes its committed receipt/version.
            previous = db.execute(
                select(SyncOperation)
                .where(
                    SyncOperation.user_id == locked_user.id,
                    SyncOperation.client_op_id == operation.client_op_id,
                )
                .execution_options(populate_existing=True)
            ).scalar_one_or_none()
            if previous:
                if previous.protocol_version != 1:
                    raise HTTPException(status_code=409, detail="Operation ID belongs to another sync protocol")
                accepted.append(
                    {
                        "client_op_id": operation.client_op_id,
                        "entity_id": previous.entity_id,
                        "server_version": previous.server_version,
                        "created": False,
                    }
                )
                continue
            raw_version = operation.payload.get("server_version")
            existing = _current_entity(
                db, operation.entity, operation.entity_id, locked_user.id
            )
            if operation.entity == 'budgets':
                canonical = budget_with_same_key(db, locked_user, operation.payload)
                if canonical and canonical.id != operation.entity_id:
                    conflicts.append({
                        'client_op_id': operation.client_op_id,
                        'entity_id': operation.entity_id,
                        'canonical_entity_id': canonical.id,
                        'reason': 'month/category budget already exists',
                    })
                    continue
            if has_newer_server_version(existing, locked_user, raw_version):
                conflicts.append(
                    {
                        "client_op_id": operation.client_op_id,
                        "entity_id": operation.entity_id,
                        "reason": "server has a newer version",
                    }
                )
                continue

            locked_user.sync_version += 1
            server_version = locked_user.sync_version
            db.flush()
            if operation.entity == "transactions":
                _save_tx(
                    db,
                    locked_user,
                    _normalise_tx_payload(
                        _attach_latest_rate(db, operation.payload),
                        client_op_id=operation.client_op_id,
                        entity_id=operation.entity_id,
                    ),
                    deleted=operation.type == "delete",
                    server_version=server_version,
                )
            elif operation.entity == "accounts":
                data = dict(operation.payload)
                data["id"] = operation.entity_id
                if operation.type != "delete":
                    data = normalize_v1_account(db, locked_user, operation, data, existing)
                _save_account(
                    db,
                    locked_user,
                    data,
                    deleted=operation.type == "delete",
                    server_version=server_version,
                )
            elif operation.entity == "categories":
                data = dict(operation.payload)
                data["id"] = operation.entity_id
                _save_category(
                    db,
                    locked_user,
                    data,
                    server_version=server_version,
                    active=operation.type != "delete",
                )
            else:
                data = dict(operation.payload)
                data["id"] = operation.entity_id
                data.setdefault("month", datetime.now(timezone.utc).strftime("%Y-%m"))
                data.setdefault("category_id", "other")
                data.setdefault("limit", 0.01)
                _save_budget(
                    db,
                    locked_user,
                    data,
                    server_version=server_version,
                )
            db.add(
                SyncOperation(
                    user_id=locked_user.id,
                    client_op_id=operation.client_op_id,
                    entity=operation.entity,
                    entity_id=operation.entity_id,
                    server_version=server_version,
                )
            )
            # Make the receipt visible to a later operation in this same
            # ordered batch and surface receipt failures before commit.
            db.flush()
            accepted.append(
                {
                    "client_op_id": operation.client_op_id,
                    "entity_id": operation.entity_id,
                    "server_version": server_version,
                    "created": True,
                }
            )
        db.commit()
    except BaseException:
        db.rollback()
        raise
    accepted_by_operation = {item["client_op_id"]: item for item in accepted}
    conflicts_by_operation = {item["client_op_id"]: item for item in conflicts}
    return {
        "accepted": [
            accepted_by_operation[operation.client_op_id]
            for operation in payload.operations
            if operation.client_op_id in accepted_by_operation
        ],
        "conflicts": [
            conflicts_by_operation[operation.client_op_id]
            for operation in payload.operations
            if operation.client_op_id in conflicts_by_operation
        ],
        "server_version": locked_user.sync_version,
    }


def pull(since_version: int = 0, db: Session | None = None, user: User | None = None, *, include_adjustments: bool = False, protocol: int = 1) -> dict:
    if db is None or user is None:
        raise TypeError("db and user are required")
    user = _lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
    enforce_sync_floor(user, protocol)
    watermark = user.sync_version
    transactions = (
        db.query(Transaction)
        .filter(Transaction.user_id == user.id, Transaction.server_version > since_version, Transaction.server_version <= watermark,
                *([] if include_adjustments else [Transaction.kind != "adjustment"]))
        .order_by(Transaction.server_version.asc())
        .populate_existing().all()
    )
    accounts = (
        db.query(Account)
        .filter(Account.user_id == user.id, Account.server_version > since_version, Account.server_version <= watermark)
        .order_by(Account.server_version.asc())
        .populate_existing().all()
    )
    categories = (
        db.query(Category)
        .filter(Category.user_id == user.id, Category.server_version > since_version, Category.server_version <= watermark)
        .order_by(Category.server_version.asc())
        .populate_existing().all()
    )
    budgets = (
        db.query(Budget)
        .filter(Budget.user_id == user.id, Budget.server_version > since_version, Budget.server_version <= watermark)
        .order_by(Budget.server_version.asc())
        .populate_existing().all()
    )
    return {
        "items": [_tx_json(row) for row in transactions],
        "transactions": [_tx_json(row) for row in transactions],
        "accounts": [_account_json(row) for row in accounts],
        "categories": [_category_json(row) for row in categories],
        "budgets": [_budget_json(row) for row in budgets],
        "server_version": user.sync_version,
    }
