import unittest


class QuickEntryModuleTest(unittest.TestCase):
    def test_quick_entry_router_and_service_are_public_module_boundaries(self):
        from app.quick_entry.router import router
        from app.quick_entry.schemas import DraftIn
        from app.quick_entry.service import make_draft

        self.assertIsNotNone(router)
        self.assertTrue(callable(make_draft))
        self.assertEqual(DraftIn(text="午餐 30 元").text, "午餐 30 元")


if __name__ == "__main__":
    unittest.main()
