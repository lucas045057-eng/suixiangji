from __future__ import annotations

from datetime import datetime, timezone
from fastapi import APIRouter

from .auth.router import router as auth_router
from .backup.router import router as backup_router
from .config import get_settings
from .quick_entry.router import router as quick_entry_router
from .services.agent import configured_model
from .insights.router import router as insights_router
from .sync.router import router as sync_router


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
