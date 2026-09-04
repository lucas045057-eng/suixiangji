import unittest
from datetime import date
from decimal import Decimal

from app.domain import (
    AccountRecord,
    TransactionRecord,
    calculate_cny,
    classify_natural_language,
    monthly_metrics,
    push_idempotent,
)


class DomainRulesTest(unittest.TestCase):
    def test_natural_language_returns_confirmable_draft(self):
        draft = classify_natural_language("今天打车 23 元，微信支付", today=date(2026, 9, 3))
        self.assertEqual(draft["kind"], "expense")
        self.assertEqual(draft["amount"], Decimal("23"))
        self.assertEqual(draft["currency"], "CNY")
        self.assertEqual(draft["category_hint"], "交通")
        self.assertEqual(draft["account_hint"], "微信")
        self.assertEqual(draft["occurred_on"], date(2026, 9, 3))
        self.assertTrue(draft["requires_confirmation"])

    def test_missing_exchange_rate_does_not_guess(self):
        converted = calculate_cny(Decimal("100"), "USD", None)
        self.assertIsNone(converted["cny_amount"])
        self.assertIsNone(converted["exchange_rate"])
        self.assertEqual(converted["conversion_status"], "pending")

    def test_transfer_is_not_income_or_expense(self):
        rows = [
            TransactionRecord("a", "expense", Decimal("32"), "CNY", Decimal("32"), "餐饮", date(2026, 9, 3)),
            TransactionRecord("b", "income", Decimal("100"), "CNY", Decimal("100"), "工资", date(2026, 9, 2)),
            TransactionRecord("c", "transfer", Decimal("200"), "CNY", Decimal("200"), None, date(2026, 9, 2)),
        ]
        metrics = monthly_metrics(rows, "2026-09")
        self.assertEqual(metrics["income"], Decimal("100"))
        self.assertEqual(metrics["expense"], Decimal("32"))
        self.assertEqual(metrics["balance"], Decimal("68"))
        self.assertEqual(metrics["category_totals"]["餐饮"], Decimal("32"))

    def test_monthly_metrics_marks_unconverted_amounts(self):
        rows = [
            TransactionRecord("a", "expense", Decimal("10"), "USD", None, "交通", date(2026, 9, 3)),
        ]
        metrics = monthly_metrics(rows, "2026-09")
        self.assertEqual(metrics["pending_conversion_count"], 1)
        self.assertEqual(metrics["expense"], Decimal("0"))

    def test_sync_retry_with_same_client_operation_is_idempotent(self):
        store = {}
        existing_ops = {}
        row = {"client_op_id": "device-1:1", "id": "tx-1", "kind": "expense"}
        first = push_idempotent(store, existing_ops, row, server_version=0)
        second = push_idempotent(store, existing_ops, row, server_version=first["server_version"])
        self.assertTrue(first["created"])
        self.assertFalse(second["created"])
        self.assertEqual(first["server_version"], second["server_version"])
        self.assertEqual(len(store), 1)


if __name__ == "__main__":
    unittest.main()
