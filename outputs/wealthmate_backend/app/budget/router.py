from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..models import User
from . import service as budget_service
from .schemas import BudgetIn, BudgetPatch


router = APIRouter()


@router.get("/budgets")
def list_budgets(
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return budget_service.list_budgets(db, user, month)


@router.post("/budgets")
def create_budget(
    payload: BudgetIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return budget_service.create_budget(db, user, payload)


@router.patch("/budgets/{budget_id}")
def update_budget(
    budget_id: str,
    payload: BudgetPatch,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return budget_service.update_budget(db, user, budget_id, payload)


@router.delete("/budgets/{budget_id}")
def delete_budget(
    budget_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return budget_service.delete_budget(db, user, budget_id)
