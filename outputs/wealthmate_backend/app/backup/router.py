from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from ..core.protocol import sync_protocol
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
    protocol: int = Depends(sync_protocol),
) -> dict:
    return _response(service.export_backup, db, user, protocol=protocol)


@router.post("/backup/restore", dependencies=[Depends(limit_auth)])
def backup_restore(
    payload: RestoreIn,
    db: Session = Depends(get_db),
    user: User = Depends(_user),
    protocol: int = Depends(sync_protocol),
) -> dict:
    return _response(service.restore_backup, payload, db, user, protocol=protocol)


def _response(call, *args, **kwargs):
    try:
        return call(*args, **kwargs)
    except HTTPException as exc:
        if exc.status_code == 426:
            return JSONResponse(status_code=426, content=exc.detail)
        raise
