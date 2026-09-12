import unittest
from datetime import date
from decimal import Decimal

from app.insights.domain import monthly_stats, period_stats
from app.insights.service import deterministic_report
from app.domain import TransactionRecord


class InsightsDomainTest(unittest.TestCase):
    def setUp(self):
        self.rows = [
            TransactionRecord(
                "income", "income", Decimal("1000"), "CNY", Decimal("1000"), "工资", date(2026, 9, 1)
            ),
            TransactionRecord(
                "expense", "expense", Decimal("32"), "CNY", Decimal("32"), "餐饮", date(2026, 9, 2), account_id="cash", account_name="现金"
            ),
            TransactionRecord(
                "pending", "expense", Decimal("10"), "USD", None, "交通", date(2026, 9, 3), account_id="cash", account_name="现金"
            ),
        ]

    def test_monthly_stats_preserve_deterministic_metrics_and_pending_fx(self):
        metrics = monthly_stats(self.rows, "2026-09")

        self.assertEqual(metrics["income"], Decimal("1000.00"))
        self.assertEqual(metrics["expense"], Decimal("32.00"))
        self.assertEqual(metrics["balance"], Decimal("968.00"))
        self.assertEqual(metrics["pending_conversion_count"], 1)

    def test_period_stats_zero_fill_series_and_account_totals(self):
        metrics = period_stats(self.rows, "month", date(2026, 9, 1), date(2026, 9, 3))

        self.assertEqual(len(metrics["expense_series"]), 3)
        self.assertEqual(metrics["expense_series"][0]["expense"], Decimal("0.00"))
        self.assertEqual(metrics["expense_series"][1]["expense"], Decimal("32.00"))
        self.assertEqual(metrics["expense_by_account"]["现金"], Decimal("32.00"))

    def test_deterministic_report_fallback_keeps_numbers_separate_from_ai(self):
        report = deterministic_report(
            {"income": 1000, "expense": 32, "balance": 968, "savings_rate": 96.8, "data_sufficient": True},
            None,
        )

        self.assertIn("1000.00", report)
        self.assertIn("32.00", report)


if __name__ == "__main__":
    unittest.main()
