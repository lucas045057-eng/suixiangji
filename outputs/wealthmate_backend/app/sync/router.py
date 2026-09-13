from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user as _user
from ..db import get_db
from ..models import User
from . import service
from .schemas import SyncPushIn


router = APIRouter()


@router.post("/sync/push")
def sync_push(
    payload: SyncPushIn,
    db: Session = Depends(get_db),
    user: User = Depends(_user),
) -> dict:
    return service.push(payload, db, user)


@router.get("/sync/pull")
def sync_pull(
    since_version: int = 0,
    db: Session = Depends(get_db),
    user: User = Depends(_user),
) -> dict:
    return service.pull(since_version, db, user)
