"""Extra provider request headers configured as a JSON object string."""
from __future__ import annotations

import json

INVALID_MESSAGE = "LLM extra headers 配置无效"

# The adapters build these themselves; a configured value must never replace
# them (a stray header would silently redirect credentials or encoding).
RESERVED_HEADERS = frozenset({"authorization", "content-type"})


def extra_headers(raw: str) -> dict[str, str]:
    """Parses ``WEALTHMATE_LLM_EXTRA_HEADERS`` into request headers.

    An empty value means "no extra headers", so deployments that do not set
    the variable keep the exact request shape they had before. Anything that
    is not a JSON object of string values (or that tries to use a reserved
    header) is a configuration error and fails closed.
    """
    if not raw or not raw.strip():
        return {}
    try:
        value = json.loads(raw)
    except ValueError:
        raise RuntimeError(INVALID_MESSAGE) from None
    if not isinstance(value, dict):
        raise RuntimeError(INVALID_MESSAGE)
    headers: dict[str, str] = {}
    for key, item in value.items():
        if not isinstance(key, str) or not isinstance(item, str):
            raise RuntimeError(INVALID_MESSAGE)
        name = key.strip().lower()
        if not name or name in RESERVED_HEADERS or name in headers:
            raise RuntimeError(INVALID_MESSAGE)
        if any(ord(char) < 32 or ord(char) == 127 for char in name + item):
            raise RuntimeError(INVALID_MESSAGE)
        headers[name] = item
    return headers
