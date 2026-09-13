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
from .schemas import RestoreIn
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
from .sync.ordering import order_operations as _order_sync_operations
from .sync.router import router as sync_router
from .sync.service import pull as sync_pull
from .sync.service import push as sync_push


router = APIRouter()
router.include_router(auth_router)
router.include_router(quick_entry_router)
router.include_router(insights_router)
router.include_router(sync_router)


_account_json = assets_service.account_json
_save_account = assets_service.save_account


@router.get("/health")
def health() -> dict:
    return {
        "status": "ok",
        "service": "suixiangji-v1",
        "git_sha": get_settings().git_sha,
        "server_time": datetime.now(timezone.utc),
    }


def stats(
    *,
    month: str | None = None,
    period: str | None = None,
    start: str | None = None,
    end: str | None = None,
    db: Session,
    user: User,
) -> dict:
    """Compatibility façade; the Insights router owns the HTTP endpoint."""
    return insights_service.stats(
        db,
        user,
        month=month,
        period=period,  # type: ignore[arg-type]
        start=start,
        end=end,
    )


async def monthly_report(month: str, force: bool = False, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    return await insights_service.monthly_report(db, user, month, force=force)

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
