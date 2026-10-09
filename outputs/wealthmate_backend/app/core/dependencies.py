from fastapi import Depends, Request
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import User


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def get_current_user(
    request: Request,
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    from ..auth.service import get_current_user as resolve_current_user

    return resolve_current_user(
        db, token, for_update=request.method not in {'GET', 'HEAD', 'OPTIONS'}
    )
