from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..models import User
from . import service as assets_service
from .schemas import AccountIn, RateIn


router = APIRouter()


@router.get("/accounts")
def list_accounts(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.list_accounts(db, user)


@router.post("/accounts")
def create_account(
    payload: AccountIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.create_account(db, user, payload)


@router.patch("/accounts/{account_id}")
def update_account(
    account_id: str,
    payload: AccountIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.update_account(db, user, account_id, payload)


@router.delete("/accounts/{account_id}")
def delete_account(
    account_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.delete_account(db, user, account_id)


@router.get("/wealth")
def wealth(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.wealth(db, user)


@router.get("/exchange/rates")
async def exchange_rate(
    base: str,
    quote: str = "CNY",
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return await assets_service.exchange_rate(db, user, base, quote)


@router.post("/exchange/rates")
def save_exchange_rate(
    payload: RateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return assets_service.save_exchange_rate(db, user, payload)
