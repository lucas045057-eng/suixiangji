from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.orm import Session

from ..assets.service import account_json as _account_json
from ..assets.service import save_account as _save_account
from ..budget.service import budget_json as _budget_json
from ..budget.service import save_budget as _save_budget
from ..ledger.service import _attach_latest_rate
from ..ledger.service import _category_json
from ..ledger.service import _normalise_tx_payload
from ..ledger.service import _save_category
from ..ledger.service import _save_tx
from ..ledger.service import _tx_json
from ..models import Account, Budget, Category, SyncOperation, Transaction, User
from .conflict import has_newer_server_version
from .ordering import order_operations
from .schemas import SyncPushIn


def push(payload: SyncPushIn, db: Session, user: User) -> dict:
    accepted = []
    conflicts = []
    ordered_operations = order_operations(payload.operations)
    for operation in ordered_operations:
        previous = (
            db.query(SyncOperation)
            .filter(
                SyncOperation.user_id == user.id,
                SyncOperation.client_op_id == operation.client_op_id,
            )
            .first()
        )
        if previous:
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
        existing = {
            "transactions": db.get(Transaction, operation.entity_id),
            "accounts": db.get(Account, operation.entity_id),
            "categories": db.get(Category, operation.entity_id),
            "budgets": db.get(Budget, operation.entity_id),
        }[operation.entity]
        if has_newer_server_version(existing, user, raw_version):
            conflicts.append(
                {
                    "client_op_id": operation.client_op_id,
                    "entity_id": operation.entity_id,
                    "reason": "server has a newer version",
                }
            )
            continue
        user.sync_version += 1
        if operation.entity == "transactions":
            row = _save_tx(
                db,
                user,
                _normalise_tx_payload(
                    _attach_latest_rate(db, operation.payload),
                    client_op_id=operation.client_op_id,
                    entity_id=operation.entity_id,
                ),
                deleted=operation.type == "delete",
                server_version=user.sync_version,
            )
        elif operation.entity == "accounts":
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            data.setdefault("name", operation.entity_id)
            row = _save_account(
                db,
                user,
                data,
                deleted=operation.type == "delete",
                server_version=user.sync_version,
            )
        elif operation.entity == "categories":
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            row = _save_category(
                db,
                user,
                data,
                server_version=user.sync_version,
                active=operation.type != "delete",
            )
        else:
            data = dict(operation.payload)
            data["id"] = operation.entity_id
            data.setdefault("month", datetime.now(timezone.utc).strftime("%Y-%m"))
            data.setdefault("category_id", "other")
            data.setdefault("limit", 0.01)
            row = _save_budget(
                db,
                user,
                data,
                server_version=user.sync_version,
            )
        db.add(
            SyncOperation(
                user_id=user.id,
                client_op_id=operation.client_op_id,
                entity=operation.entity,
                entity_id=operation.entity_id,
                server_version=user.sync_version,
            )
        )
        accepted.append(
            {
                "client_op_id": operation.client_op_id,
                "entity_id": operation.entity_id,
                "server_version": user.sync_version,
                "created": True,
            }
        )
        if operation.entity in {"accounts", "categories"} and operation.type == "upsert":
            db.flush()
    db.commit()
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
        "server_version": user.sync_version,
    }


def pull(since_version: int = 0, db: Session | None = None, user: User | None = None) -> dict:
    if db is None or user is None:
        raise TypeError("db and user are required")
    transactions = (
        db.query(Transaction)
        .filter(Transaction.user_id == user.id, Transaction.server_version > since_version)
        .order_by(Transaction.server_version.asc())
        .all()
    )
    accounts = (
        db.query(Account)
        .filter(Account.user_id == user.id, Account.server_version > since_version)
        .order_by(Account.server_version.asc())
        .all()
    )
    categories = (
        db.query(Category)
        .filter(Category.user_id == user.id, Category.server_version > since_version)
        .order_by(Category.server_version.asc())
        .all()
    )
    budgets = (
        db.query(Budget)
        .filter(Budget.user_id == user.id, Budget.server_version > since_version)
        .order_by(Budget.server_version.asc())
        .all()
    )
    return {
        "items": [_tx_json(row) for row in transactions],
        "transactions": [_tx_json(row) for row in transactions],
        "accounts": [_account_json(row) for row in accounts],
        "categories": [_category_json(row) for row in categories],
        "budgets": [_budget_json(row) for row in budgets],
        "server_version": user.sync_version,
    }
