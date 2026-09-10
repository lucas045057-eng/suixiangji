from __future__ import annotations

from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models import Category, User
from ..core.security import create_token, decode_token, hash_password, verify_password
from .schemas import LoginIn, PasswordChange, ProfilePatch


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


def login(db: Session, payload: LoginIn) -> dict:
    settings = get_settings()
    user = db.query(User).filter(User.username == payload.username).first()
    if user:
        if not verify_password(payload.password, user.password_hash):
            raise HTTPException(status_code=401, detail="用户名或密码错误")
    elif payload.username != settings.demo_username or payload.password != settings.demo_password:
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    if not user:
        user = User(
            id=str(uuid4()),
            username=payload.username,
            password_hash=hash_password(payload.password),
            display_name=payload.username,
        )
        db.add(user)
        db.flush()
        current_version = user.sync_version or 0
        for name, kind in (
            ("餐饮", "expense"),
            ("交通", "expense"),
            ("住房", "expense"),
            ("工资", "income"),
            ("购物", "expense"),
        ):
            current_version += 1
            db.add(
                Category(
                    id=str(uuid4()),
                    user_id=user.id,
                    name=name,
                    kind=kind,
                    server_version=current_version,
                )
            )
        user.sync_version = current_version
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
    token_version = claims.get("auth_version")
    if token_version is not None and int(token_version) != (found.auth_version or 0):
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    return found


def profile(user: User) -> dict:
    return profile_json(user)


def update_profile(db: Session, user: User, payload: ProfilePatch) -> dict:
    changed_credentials = False
    if payload.username is not None:
        username = payload.username.strip()
        if not username:
            raise HTTPException(status_code=422, detail="用户名不能为空")
        existing = (
            db.query(User)
            .filter(User.username == username, User.id != user.id)
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
    db.commit()
    return profile_json(user, include_token=True)


def change_password(db: Session, user: User, payload: PasswordChange) -> dict:
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=401, detail="当前密码错误")
    user.password_hash = hash_password(payload.new_password)
    user.auth_version = (user.auth_version or 0) + 1
    db.commit()
    return profile_json(user, include_token=True)
