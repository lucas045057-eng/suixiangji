from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user as _user
from ..core.rate_limit import limit_auth
from ..db import get_db
from ..models import User
from .schemas import RestoreIn
from . import service


router = APIRouter()


@router.get("/backup/export", dependencies=[Depends(limit_auth)])
def backup_export(
    db: Session = Depends(get_db),
    user: User = Depends(_user),
) -> dict:
    return service.export_backup(db, user)


@router.post("/backup/restore", dependencies=[Depends(limit_auth)])
def backup_restore(
    payload: RestoreIn,
    db: Session = Depends(get_db),
    user: User = Depends(_user),
) -> dict:
    return service.restore_backup(payload, db, user)
