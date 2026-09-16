import unittest
from decimal import Decimal


class QuickEntryModuleTest(unittest.TestCase):
    def test_quick_entry_router_and_service_are_public_module_boundaries(self):
        from app.quick_entry.router import router
        from app.quick_entry.schemas import DraftIn
        from app.quick_entry.service import make_draft

        self.assertIsNotNone(router)
        self.assertTrue(callable(make_draft))
        self.assertEqual(DraftIn(text="午餐 30 元").text, "午餐 30 元")

    def test_quick_entry_parses_chinese_amount_units(self):
        from app.quick_entry.domain import classify_natural_language

        examples = {
            "午餐 16块86 支付宝": Decimal("16.86"),
            "午餐 16元8角6分 支付宝": Decimal("16.86"),
            "午餐 16元8毛6 支付宝": Decimal("16.86"),
            "午餐 两元 支付宝": Decimal("2.00"),
            "午餐 两块 支付宝": Decimal("2.00"),
            "午餐 两块五 支付宝": Decimal("2.50"),
            "午餐 2块5 支付宝": Decimal("2.50"),
            "午餐 16.86元 支付宝": Decimal("16.86"),
            "午餐 32元 支付宝": Decimal("32.00"),
        }

        for text, expected in examples.items():
            with self.subTest(text=text):
                draft = classify_natural_language(text)

                self.assertEqual(draft["amount"], expected)

    def test_quick_entry_does_not_invent_unparseable_amounts(self):
        from app.quick_entry.domain import classify_natural_language

        examples = [
            "午餐好多钱 支付宝",
            "午餐 十百元 支付宝",
            "午餐 16.860元 支付宝",
            "午餐 16元5厘 支付宝",
            "午餐 16元8角6厘 支付宝",
            "午餐 0元 支付宝",
        ]

        for text in examples:
            with self.subTest(text=text):
                draft = classify_natural_language(text)

                self.assertIsNone(draft["amount"])
                self.assertIn("amount", draft["missing_fields"])
                self.assertIn("请输入金额", draft["missing_facts"])

    def test_quick_entry_parses_chinese_ten_thousand_shorthand(self):
        from app.quick_entry.domain import classify_natural_language

        examples = {
            "午餐 一万二元 支付宝": Decimal("12000.00"),
            "午餐 二万三元 支付宝": Decimal("23000.00"),
        }

        for text, expected in examples.items():
            with self.subTest(text=text):
                self.assertEqual(classify_natural_language(text)["amount"], expected)

    def test_quick_entry_exposes_missing_facts_with_missing_fields(self):
        from app.quick_entry.domain import classify_natural_language

        draft = classify_natural_language("午餐 32元")

        self.assertEqual(draft["missing_fields"], ["account"])
        self.assertEqual(draft["missing_facts"], ["请选择支付账户"])


if __name__ == "__main__":
    unittest.main()
