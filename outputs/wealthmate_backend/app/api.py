from __future__ import annotations

from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .auth.router import router as auth_router
from .backup.router import router as backup_router
from .backup import service as backup_service
from .config import get_settings
from .core.dependencies import get_current_user as _user
from .db import get_db
from .models import User
from .quick_entry.router import agent_draft, router as quick_entry_router
from .quick_entry.schemas import DraftIn
from .schemas import RestoreIn
from .services.agent import configured_model
from .insights.router import router as insights_router
from .insights import service as insights_service
from .insights.service import json_metrics as _json_metrics
from .insights.service import records as _records
from .sync.ordering import order_operations as _order_sync_operations
from .sync.router import router as sync_router
from .sync import service as sync_service
from .sync.schemas import SyncPushIn


router = APIRouter()
router.include_router(auth_router)
router.include_router(backup_router)
router.include_router(quick_entry_router)
router.include_router(insights_router)
router.include_router(sync_router)


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


def sync_push(payload: SyncPushIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    """Compatibility façade; the Sync router owns the HTTP route."""
    return sync_service.push(payload, db, user)


def sync_pull(since_version: int = 0, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    """Compatibility façade; the Sync router owns the HTTP route."""
    return sync_service.pull(since_version, db, user)


def backup_export(db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    """Compatibility façade; the Backup router owns the HTTP route."""
    return backup_service.export_backup(db, user)


def backup_restore(payload: RestoreIn, db: Session = Depends(get_db), user: User = Depends(_user)) -> dict:
    """Compatibility façade; the Backup router owns the HTTP route."""
    return backup_service.restore_backup(payload, db, user)
