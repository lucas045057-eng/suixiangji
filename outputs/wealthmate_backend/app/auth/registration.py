"""Invite consumption and initial account data share the caller's transaction."""
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy import or_, update
from sqlalchemy.orm import Session

from ..core.security import hash_password
from ..models import Category, InviteCode, User


def create_user(
    db: Session,
    username: str,
    password: str,
    display_name: str | None = None,
) -> User:
    user = User(
        id=str(uuid4()),
        username=username,
        password_hash=hash_password(password),
        display_name=(display_name or "").strip() or username,
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
    return user


def consume_invite(db: Session, code: str) -> None:
    # A conditional UPDATE locks the invitation row and rechecks capacity on
    # PostgreSQL after waiting. Rollback also restores the usage count.
    result = db.execute(
        update(InviteCode)
        .where(
            InviteCode.code == code.strip(),
            InviteCode.enabled.is_(True),
            InviteCode.used_count < InviteCode.max_uses,
            or_(
                InviteCode.expires_at.is_(None),
                InviteCode.expires_at > datetime.now(timezone.utc),
            ),
        )
        .values(used_count=InviteCode.used_count + 1)
        .execution_options(synchronize_session=False)
    )
    if result.rowcount != 1:
        raise HTTPException(status_code=400, detail="邀请码无效、已过期或已用完")
