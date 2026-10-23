import unittest
from datetime import date
from decimal import Decimal

from app.assets.domain import calculate_cny
from app.insights.domain import AccountRecord, TransactionRecord, monthly_metrics
from app.quick_entry.domain import classify_natural_language


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

        asset_converted = calculate_cny(
            Decimal("100"),
            "USD",
            Decimal("7.25"),
            rate_date=date(2026, 9, 3),
            source="verified source",
        )
        self.assertEqual(asset_converted["cny_amount"], Decimal("725.00"))
        self.assertEqual(asset_converted["exchange_rate"], Decimal("7.25"))
        self.assertEqual(asset_converted["exchange_rate_date"], date(2026, 9, 3))
        self.assertEqual(asset_converted["exchange_rate_source"], "verified source")

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

if __name__ == "__main__":
    unittest.main()
