from __future__ import annotations

from typing import Any


def push_idempotent(
    store: dict[str, dict[str, Any]],
    operations: dict[str, int],
    row: dict[str, Any],
    *,
    server_version: int,
) -> dict[str, Any]:
    """Reference helper for the same client-operation idempotency contract."""
    op_id = row["client_op_id"]
    if op_id in operations:
        return {
            "created": False,
            "server_version": operations[op_id],
            "transaction": store[row["id"]],
        }
    server_version += 1
    store[row["id"]] = dict(row, server_version=server_version)
    operations[op_id] = server_version
    return {
        "created": True,
        "server_version": server_version,
        "transaction": store[row["id"]],
    }
