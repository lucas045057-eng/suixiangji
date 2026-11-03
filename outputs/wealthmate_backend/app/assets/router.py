from datetime import date
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..db import get_db
from ..core.protocol import adjustment_view
from ..models import User
from . import service as assets_service
from .schemas import AccountIn, AccountPatch, RateIn, CalibrationIn, ReverseCalibrationIn
from . import calibration


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
    payload: AccountPatch,
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
    include_adjustments: bool = Depends(adjustment_view),
    as_of_date: date | None = None,
) -> dict:
    return assets_service.wealth(db, user, include_adjustments=include_adjustments, as_of_date=as_of_date)


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


def _calibration_response(command, *args):
    try:
        return command(*args)
    except HTTPException as exc:
        if isinstance(exc.detail, dict) and "code" in exc.detail:
            return JSONResponse(status_code=exc.status_code,
                                content={"code": exc.detail["code"], "detail": exc.detail["message"]})
        raise


@router.post("/assets/accounts/{account_id}/calibration")
def calibrate_account(account_id: str, payload: CalibrationIn,
                      db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _calibration_response(calibration.calibrate, db, user, account_id, payload)


@router.post("/assets/accounts/{account_id}/calibrations/{transaction_id}/reverse")
def reverse_calibration(account_id: str, transaction_id: str, payload: ReverseCalibrationIn,
                        db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return _calibration_response(calibration.reverse, db, user, account_id, transaction_id, payload)
