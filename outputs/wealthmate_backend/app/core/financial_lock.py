from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session
from ..models import User


def lock_current_user(
    db: Session,
    user_id: str,
    *,
    verified_auth_version: int | None = None,
) -> User:
    """Lock and refresh the authoritative User row for one financial write transaction."""
    locked = db.execute(
        select(User)
        .where(User.id == user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).scalar_one_or_none()
    if locked is None:
        raise HTTPException(status_code=401, detail='登录已失效，请重新登录')
    # The authentication dependency may already have populated this identity
    # in the Session before the row lock was acquired. Refresh explicitly so
    # version allocation starts from the value observed after lock wait.
    db.refresh(locked)
    if (
        verified_auth_version is not None
        and (locked.auth_version or 0) != verified_auth_version
    ):
        raise HTTPException(status_code=401, detail='登录已失效，请重新登录')
    return locked
