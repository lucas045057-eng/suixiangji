from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user
from ..core.rate_limit import limit_auth
from ..db import get_db
from ..models import User
from . import service as auth_service
from .schemas import DeleteUserIn, LoginIn, PasswordChange, ProfilePatch, RegisterIn


router = APIRouter()


@router.post("/auth/register", status_code=201, dependencies=[Depends(limit_auth)])
def register(payload: RegisterIn, db: Session = Depends(get_db)) -> dict:
    return auth_service.register(db, payload)


@router.post("/auth/login", dependencies=[Depends(limit_auth)])
def login(payload: LoginIn, db: Session = Depends(get_db)) -> dict:
    return auth_service.login(db, payload)


@router.get("/auth/me")
def profile(user: User = Depends(get_current_user)) -> dict:
    return auth_service.profile(user)


@router.patch("/auth/me")
def update_profile(
    payload: ProfilePatch,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return auth_service.update_profile(db, user, payload)


@router.post("/auth/password")
def change_password(
    payload: PasswordChange,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return auth_service.change_password(db, user, payload)


@router.delete("/auth/me")
def delete_user(
    payload: DeleteUserIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return auth_service.delete_user(db, user, payload)
