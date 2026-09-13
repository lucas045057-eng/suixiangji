from __future__ import annotations

from typing import Any


def has_newer_server_version(existing: Any, user: Any, raw_version: Any) -> bool:
    """Preserve the existing optimistic-conflict predicate exactly."""
    return bool(
        existing
        and existing.user_id == user.id
        and raw_version is not None
        and int(raw_version) < existing.server_version
    )
