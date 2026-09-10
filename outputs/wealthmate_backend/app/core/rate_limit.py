"""Bounded process-local fixed windows; not a distributed rate limiter."""
from threading import Lock
from time import monotonic

from fastapi import HTTPException, Request

from ..config import get_settings


class AuthLimiter:
    def __init__(self, *, max_keys=4096, window_seconds=60, clock=monotonic):
        self.max_keys = max_keys
        self.window_seconds = window_seconds
        self.clock = clock
        self._entries = {}
        self._lock = Lock()

    def clear(self):
        with self._lock:
            self._entries.clear()

    def allow(self, key, limit):
        now = self.clock()
        with self._lock:
            self._entries = {
                key: value
                for key, value in self._entries.items()
                if now - value[0] < self.window_seconds
            }
            start, count = self._entries.get(key, (now, 0))
            if count >= limit or (key not in self._entries and len(self._entries) >= self.max_keys):
                return False
            self._entries[key] = (start, count + 1)
            return True


auth_limiter = AuthLimiter()


def limit_auth(request: Request):
    settings = get_settings()
    limit = (
        settings.auth_register_limit
        if request.url.path.endswith("/register")
        else settings.auth_login_limit
    )
    # Ignore forwarded headers here; only the trusted ASGI proxy may set client.
    key = (request.client.host if request.client else "unknown", request.url.path)
    if not auth_limiter.allow(key, limit):
        raise HTTPException(
            status_code=429,
            detail="尝试过于频繁，请稍后再试",
            headers={"Retry-After": str(auth_limiter.window_seconds)},
        )
