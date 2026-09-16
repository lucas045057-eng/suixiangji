import os
import tempfile
import unittest

from sqlalchemy.orm import sessionmaker


class CategoryTypeCouplingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        os.environ["WEALTHMATE_DATABASE_URL"] = (
            f"sqlite:///{os.path.join(cls.tempdir.name, 'category-coupling.db')}"
        )
        os.environ["WEALTHMATE_DEMO_USERNAME"] = "category-user"
        os.environ["WEALTHMATE_DEMO_PASSWORD"] = "category-password"
        os.environ["WEALTHMATE_DEMO_ENABLED"] = "true"
        os.environ["WEALTHMATE_ENVIRONMENT"] = "test"
        os.environ["WEALTHMATE_JWT_SECRET"] = "category-secret"

        from app.config import get_settings

        get_settings.cache_clear()
        from app import db
        from app.main import app
        from fastapi.testclient import TestClient

        # test_api tears down the process-global engine before this module is
        # collected. Rebind the existing db module to this class's database
        # so the test remains order-independent without changing production.
        db.engine.dispose()
        db.engine = db._engine()
        db.SessionLocal = sessionmaker(
            bind=db.engine, autoflush=False, expire_on_commit=False
        )
        db.Base.metadata.create_all(bind=db.engine)
        cls.client = TestClient(app)
        response = cls.client.post(
            "/auth/login",
            json={"username": "category-user", "password": "category-password"},
        )
        assert response.status_code == 200, response.text
        cls.headers = {
            "authorization": f"Bearer {response.json()['access_token']}"
        }

    @classmethod
    def tearDownClass(cls):
        from app import db

        db.engine.dispose()
        cls.tempdir.cleanup()

    def setUp(self):
        account = self.client.post(
            "/accounts",
            headers=self.headers,
            json={"id": "category-coupling-wallet", "name": "类型钱包", "kind": "asset"},
        )
        self.assertIn(account.status_code, (200, 409), account.text)
        expense = self.client.post(
            "/categories",
            headers=self.headers,
            json={"id": "category-coupling-food", "name": "餐饮", "kind": "expense"},
        )
        self.assertIn(expense.status_code, (200, 409), expense.text)
        income = self.client.post(
            "/categories",
            headers=self.headers,
            json={"id": "category-coupling-salary", "name": "工资", "kind": "income"},
        )
        self.assertIn(income.status_code, (200, 409), income.text)

    def test_http_create_rejects_expense_using_income_category(self):
        response = self.client.post(
            "/transactions",
            headers=self.headers,
            json={
                "id": "category-coupling-http",
                "client_op_id": "category-coupling:http",
                "kind": "expense",
                "amount": 18,
                "currency": "CNY",
                "account_id": "category-coupling-wallet",
                "category_id": "category-coupling-salary",
                "occurred_on": "2026-09-15",
            },
        )

        self.assertEqual(response.status_code, 422, response.text)
        self.assertIn("分类类型", response.text)

    def test_service_save_rejects_expense_using_income_category(self):
        from fastapi import HTTPException

        from app.db import SessionLocal
        from app.ledger.domain import normalise_transaction_payload
        from app.ledger.service import save_transaction
        from app.models import User

        db = SessionLocal()
        try:
            user = db.query(User).filter(User.username == "category-user").one()
            with self.assertRaises(HTTPException) as raised:
                save_transaction(
                    db,
                    user,
                    normalise_transaction_payload(
                        {
                            "id": "category-coupling-service",
                            "client_op_id": "category-coupling:service",
                            "kind": "expense",
                            "amount": 20,
                            "currency": "CNY",
                            "account_id": "category-coupling-wallet",
                            "category_id": "category-coupling-salary",
                            "occurred_on": "2026-09-15",
                        }
                    ),
                    server_version=user.sync_version + 1,
                )
            self.assertEqual(raised.exception.status_code, 422)
            self.assertIn("分类类型", raised.exception.detail)
        finally:
            db.close()

    def test_sync_push_rejects_expense_using_income_category(self):
        response = self.client.post(
            "/sync/push",
            headers=self.headers,
            json={
                "operations": [
                    {
                        "client_op_id": "category-coupling:sync",
                        "entity": "transactions",
                        "entity_id": "category-coupling-sync",
                        "type": "upsert",
                        "payload": {
                            "id": "category-coupling-sync",
                            "type": "expense",
                            "amount": 22,
                            "currency": "CNY",
                            "account_id": "category-coupling-wallet",
                            "category_id": "category-coupling-salary",
                            "occurred_on": "2026-09-15",
                        },
                    }
                ]
            },
        )

        self.assertEqual(response.status_code, 422, response.text)
        self.assertIn("分类类型", response.text)
        rows = self.client.get(
            "/transactions?include_deleted=true", headers=self.headers
        ).json()["items"]
        self.assertFalse(any(row["id"] == "category-coupling-sync" for row in rows))

    def test_transfer_keeps_existing_category_semantics(self):
        response = self.client.post(
            "/transactions",
            headers=self.headers,
            json={
                "id": "category-coupling-transfer",
                "client_op_id": "category-coupling:transfer",
                "kind": "transfer",
                "amount": 5,
                "currency": "CNY",
                "from_account_id": "category-coupling-wallet",
                "to_account_id": "category-coupling-wallet",
                "category_id": "category-coupling-salary",
                "occurred_on": "2026-09-15",
            },
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["category_id"], "category-coupling-salary")


if __name__ == "__main__":
    unittest.main()
