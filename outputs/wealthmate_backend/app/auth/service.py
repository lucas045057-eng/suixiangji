from __future__ import annotations

from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models import (
    Account,
    AgentLog,
    Budget,
    Category,
    MonthlyReport,
    NetWorthSnapshot,
    SyncOperation,
    Transaction,
    User,
)
from ..core.security import create_token, decode_token, hash_password, verify_password
from .registration import consume_invite, create_user
from .schemas import DeleteUserIn, LoginIn, PasswordChange, ProfilePatch, RegisterIn


def profile_json(user: User, *, include_token: bool = False) -> dict:
    result = {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
        "quick_memories": user.quick_memories or [],
    }
    if include_token:
        result["access_token"] = create_token(
            user.id,
            user.username,
            user.auth_version or 0,
        )
        result["token_type"] = "bearer"
    return result


def _lock_auth_user(db: Session, user: User) -> User:
    """Serialize sensitive account mutations, revalidate after acquiring lock."""
    verified_version = user.auth_version or 0
    current = (
        db.query(User)
        .filter(User.id == user.id)
        .populate_existing()
        .with_for_update()
        .first()
    )
    if current is None or (current.auth_version or 0) != verified_version:
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    return current


def register(db: Session, payload: RegisterIn) -> dict:
    try:
        consume_invite(db, payload.invite_code)
        user = create_user(db, payload.username, payload.password, payload.display_name)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="用户名已存在") from None
    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(status_code=503, detail="注册服务暂不可用，请稍后重试") from None
    except Exception:
        db.rollback()
        raise
    return {**profile_json(user, include_token=True), "user_id": user.id}


def login(db: Session, payload: LoginIn) -> dict:
    settings = get_settings()
    username = payload.username.strip().lower()
    user = db.query(User).filter(func.lower(func.trim(User.username)) == username).first()
    if user:
        if not verify_password(payload.password, user.password_hash):
            raise HTTPException(status_code=401, detail="用户名或密码错误")
    elif (
        not settings.demo_enabled
        or username != settings.demo_username.strip().lower()
        or payload.password != settings.demo_password
    ):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    if not user:
        user = create_user(db, username, payload.password)
        db.commit()
    return {
        "access_token": create_token(
            user.id,
            user.username,
            user.auth_version or 0,
        ),
        "token_type": "bearer",
        "user_id": user.id,
        "username": user.username,
        "display_name": user.display_name or user.username,
    }


def get_current_user(db: Session, token: str) -> User:
    try:
        claims = decode_token(token)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="登录已失效") from exc
    found = db.get(User, claims.get("sub"))
    if not found:
        raise HTTPException(status_code=401, detail="用户不存在")
    if claims["auth_version"] != (found.auth_version or 0):
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    return found


def profile(user: User) -> dict:
    return profile_json(user)


def update_profile(db: Session, user: User, payload: ProfilePatch) -> dict:
    user = _lock_auth_user(db, user)
    changed_credentials = False
    if payload.username is not None:
        username = payload.username.strip()
        if not username:
            raise HTTPException(status_code=422, detail="用户名不能为空")
        existing = (
            db.query(User)
            .filter(func.lower(func.trim(User.username)) == username, User.id != user.id)
            .first()
        )
        if existing:
            raise HTTPException(status_code=409, detail="用户名已存在")
        if username != user.username:
            user.username = username
            changed_credentials = True
    if payload.display_name is not None:
        user.display_name = payload.display_name.strip()
    if payload.quick_memories is not None:
        user.quick_memories = payload.quick_memories
    if changed_credentials:
        user.auth_version = (user.auth_version or 0) + 1
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="用户名已存在") from None
    return profile_json(user, include_token=True)


def change_password(db: Session, user: User, payload: PasswordChange) -> dict:
    user = _lock_auth_user(db, user)
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="当前密码错误")
    user.password_hash = hash_password(payload.new_password)
    user.auth_version = (user.auth_version or 0) + 1
    db.commit()
    return profile_json(user, include_token=True)


def delete_user(db: Session, user: User, payload: DeleteUserIn) -> dict:
    user = _lock_auth_user(db, user)
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=403, detail="当前密码错误，账户未注销")
    # FK dependents first. Public exchange rates and invitation history remain.
    try:
        for model in (
            Transaction,
            Budget,
            SyncOperation,
            NetWorthSnapshot,
            MonthlyReport,
            AgentLog,
            Account,
            Category,
        ):
            db.query(model).filter(model.user_id == user.id).delete(
                synchronize_session=False
            )
        db.delete(user)
        db.commit()
    except Exception:
        db.rollback()
        raise
    return {"deleted": True}
