from datetime import datetime, timedelta, timezone
import base64
import hashlib
import hmac
import os
from uuid import uuid4

from jose import JWTError, jwt

from .config import get_settings


PBKDF2_ITERATIONS = 310_000


def hash_password(value: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", value.encode(), salt, PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def verify_password(value: str, hashed: str) -> bool:
    try:
        scheme, iterations, salt_text, digest_text = hashed.split("$", 3)
        if scheme != "pbkdf2_sha256":
            return False
        salt = base64.urlsafe_b64decode(salt_text.encode())
        expected = base64.urlsafe_b64decode(digest_text.encode())
        actual = hashlib.pbkdf2_hmac("sha256", value.encode(), salt, int(iterations))
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def create_token(user_id: str, username: str, auth_version: int = 0) -> str:
    settings = get_settings()
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    return jwt.encode({"sub": user_id, "username": username, "auth_version": auth_version, "exp": expires, "jti": str(uuid4())}, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str) -> dict[str, str]:
    try:
        return jwt.decode(token, get_settings().jwt_secret, algorithms=["HS256"])
    except JWTError as exc:
        raise ValueError("invalid token") from exc
