import unittest

from app.sync.ordering import order_operations
from app.sync.schemas import SyncOperationIn


def operation(entity: str, operation_type: str = "upsert", index: int = 0):
    return SyncOperationIn(
        client_op_id=f"sync-module:{index}",
        entity=entity,
        entity_id=f"{entity}-{index}",
        type=operation_type,
        payload={},
    )


class SyncModuleBoundaryTest(unittest.TestCase):
    def test_ordering_preserves_dependency_priority_and_non_upsert_positions(self):
        operations = [
            operation("transactions", index=0),
            operation("accounts", index=1),
            operation("categories", index=2),
            operation("transactions", "delete", 3),
            operation("budgets", index=4),
        ]

        ordered = order_operations(operations)

        self.assertEqual(
            [(item.entity, item.type) for item in ordered],
            [
                ("accounts", "upsert"),
                ("categories", "upsert"),
                ("transactions", "upsert"),
                ("transactions", "delete"),
                ("budgets", "upsert"),
            ],
        )


if __name__ == "__main__":
    unittest.main()
