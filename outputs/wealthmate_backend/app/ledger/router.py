from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..models import User
from . import service as ledger_service
from .schemas import CategoryIn, CategoryPatch, TransactionIn


router = APIRouter()


@router.get("/categories")
def list_categories(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.list_categories(db, user)


@router.post("/categories")
def create_category(
    payload: CategoryIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.create_category(db, user, payload)


@router.patch("/categories/{category_id}")
def update_category(
    category_id: str,
    payload: CategoryPatch,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.update_category(db, user, category_id, payload)


@router.post("/categories/{category_id}/archive")
def archive_category(
    category_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.archive_category(db, user, category_id)


@router.get("/transactions")
def list_transactions(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    include_deleted: bool = False,
) -> dict:
    return ledger_service.list_transactions(db, user, include_deleted=include_deleted)


@router.post("/transactions")
def create_transaction(
    payload: TransactionIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.create_transaction(db, user, payload)


@router.patch("/transactions/{transaction_id}")
def update_transaction(
    transaction_id: str,
    payload: TransactionIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.update_transaction(db, user, transaction_id, payload)


@router.delete("/transactions/{transaction_id}")
def delete_transaction(
    transaction_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return ledger_service.delete_transaction(db, user, transaction_id)
