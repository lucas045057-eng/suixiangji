from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..models import User
from . import service as insights_service


router = APIRouter()


@router.get("/stats")
def stats(
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    period: Literal["day", "week", "month", "custom"] | None = Query(default=None),
    start: str | None = Query(default=None),
    end: str | None = Query(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    try:
        return insights_service.stats(db, user, month=month, period=period, start=start, end=end)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/reports/monthly/{month}")
async def monthly_report(
    month: str,
    force: bool = False,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return await insights_service.monthly_report(db, user, month, force=force)

