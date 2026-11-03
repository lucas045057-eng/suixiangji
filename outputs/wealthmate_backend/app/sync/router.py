from __future__ import annotations
from fastapi import APIRouter, Depends, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy.orm import Session
from ..core.dependencies import get_current_user as _user
from ..core.protocol import sync_protocol
from ..db import get_db
from ..models import User
from . import service, v2
from .schemas import SyncPushIn, SyncPushV2In

router = APIRouter()


def _response(call, *args, **kwargs):
    try:
        return call(*args, **kwargs)
    except HTTPException as exc:
        if exc.status_code == 426:
            return JSONResponse(status_code=426, content=exc.detail)
        raise


@router.post("/sync/push")
def sync_push(payload: dict, protocol: int = Depends(sync_protocol),
              db: Session = Depends(get_db), user: User = Depends(_user)):
    try:
        parsed = (SyncPushV2In if protocol == 2 else SyncPushIn).model_validate(payload)
    except ValidationError as exc:
        raise RequestValidationError(exc.errors()) from None
    return _response(v2.push if protocol == 2 else service.push, parsed, db, user)


@router.get("/sync/pull")
def sync_pull(since_version: int = 0, protocol: int = Depends(sync_protocol),
              db: Session = Depends(get_db), user: User = Depends(_user)):
    if protocol == 2:
        return _response(v2.pull, since_version, db, user)
    return _response(service.pull, since_version, db, user)
