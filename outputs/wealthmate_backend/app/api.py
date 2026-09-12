from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .assets import service as assets_service
from .auth.router import router as auth_router
from .config import get_settings
from .core.dependencies import get_current_user as _user
from .db import get_db
from .models import Account, Budget, Category, SyncOperation, Transaction, User
from .quick_entry.router import agent_draft, router as quick_entry_router
from .quick_entry.schemas import DraftIn
from .schemas import RestoreIn, SyncPushIn
from .budget.service import budget_json as _budget_json
from .budget.service import save_budget as _save_budget
from .ledger.service import (
    _attach_latest_rate,
    _category_json,
    _normalise_tx_payload,
    _save_category,
    _save_tx,
    _tx_json,
)
from .services.agent import configured_model
from .assets.service import fetch_frankfurter_rate
from .insights.router import router as insights_router
from .insights import service as insights_service
from .insights.service import json_metrics as _json_metrics
from .insights.service import records as _records


router = APIRouter()
router.include_router(auth_router)
router.include_router(quick_entry_router)
router.include_router(insights_router)


_account_json = assets_service.account_json
_save_account = assets_service.save_account


def _order_sync_operations(operations: list) -> list:
    """Place entity dependencies before dependent upserts without moving deletes."""
    priority = {"accounts": 0, "categories": 0, "transactions": 1, "budgets": 1}
    indexed_upserts = [
        (index, operation)
        for index, operation in enumerate(operations)
        if operation.type == "upsert" and operation.entity in priority
    ]
    ordered_upserts = iter(
        operation
        for _, operation in sorted(
            indexed_upserts,
            key=lambda item: (priority[item[1].entity], item[0]),
        )
    )
    return [
        next(ordered_upserts)
        if operation.type == "upsert" and operation.entity in priority
        else operation
        for operation in operations
    ]


@router.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "service": "suixiangji-v1",
        "git_sha": get_settings().git_sha,
        "server_time": datetime.now(timezone.utc),
    }


async def monthly_report(month: str, force: bool = False, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    return await insights_service.monthly_report(db, user, month, force=force)

@router.post("/sync/push")
def sync_push(payload: SyncPushIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    accepted = []
    conflicts = []
    ordered_operations = _order_sync_operations(payload.operations)
    for operation in ordered_operations:
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
