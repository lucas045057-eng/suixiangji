from __future__ import annotations


def order_operations(operations: list) -> list:
    """Keep the existing dependency order while leaving deletes in place."""
    priority = {"accounts": 0, "categories": 0, "transactions": 1, "budgets": 1}
    indexed_upserts = [
        (index, operation)
        for index, operation in enumerate(operations)
        if operation.type == "upsert" and operation.entity in priority
    ]
    ordered_upserts = iter(
        operation
        for _, operation in sorted(
            indexed_upserts,
            key=lambda item: (priority[item[1].entity], item[0]),
        )
    )
    return [
        next(ordered_upserts)
        if operation.type == "upsert" and operation.entity in priority
        else operation
        for operation in operations
    ]
