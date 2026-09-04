import os
import tempfile
import unittest


class ApiContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        os.environ["WEALTHMATE_DATABASE_URL"] = f"sqlite:///{os.path.join(cls.tempdir.name, 'api.db')}"
        os.environ["WEALTHMATE_DEMO_USERNAME"] = "test-user"
        os.environ["WEALTHMATE_DEMO_PASSWORD"] = "test-password"
        os.environ["WEALTHMATE_JWT_SECRET"] = "test-secret"
        from app.config import get_settings

        get_settings.cache_clear()
        from fastapi.testclient import TestClient
        from app.main import app
        from app.db import Base, engine

        Base.metadata.create_all(bind=engine)
        cls.client = TestClient(app)
        response = cls.client.post("/auth/login", json={"username": "test-user", "password": "test-password"})
        assert response.status_code == 200, response.text
        cls.headers = {"authorization": f"Bearer {response.json()['access_token']}"}

    @classmethod
    def tearDownClass(cls):
        from app.db import engine

        engine.dispose()
        cls.tempdir.cleanup()

    def test_health_and_idempotent_transaction_create(self):
        self.assertEqual(self.client.get("/health").status_code, 200)
        account = self.client.post("/accounts", headers=self.headers, json={"id": "wallet", "name": "微信", "kind": "asset"})
        self.assertEqual(account.status_code, 200, account.text)
        tx = {"id": "tx-1", "client_op_id": "device-1:1", "kind": "expense", "amount": 32, "currency": "CNY", "account_id": "wallet", "category_name": "餐饮", "occurred_on": "2026-09-03", "note": "午饭"}
        first = self.client.post("/transactions", headers=self.headers, json=tx)
        second = self.client.post("/transactions", headers=self.headers, json=tx)
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        self.assertEqual(self.client.get("/transactions", headers=self.headers).json()["items"].__len__(), 1)

    def test_agent_endpoint_only_returns_a_draft(self):
        self.client.post("/accounts", headers=self.headers, json={"id": "agent-wallet", "name": "Agent微信", "kind": "asset"})
        response = self.client.post("/agent/draft", headers=self.headers, json={"text": "今天打车 23 元，微信支付"})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["type"], "expense")
        self.assertEqual(response.json()["amount"], 23.0)
        self.assertTrue(response.json()["requires_confirmation"])

    def test_transfer_is_excluded_from_stats_and_backup_round_trips(self):
        self.client.post("/accounts", headers=self.headers, json={"id": "bank", "name": "银行卡", "kind": "asset"})
        self.client.post("/transactions", headers=self.headers, json={"id": "income-1", "client_op_id": "device-1:2", "kind": "income", "amount": 100, "account_id": "bank", "occurred_on": "2026-09-02"})
        self.client.post("/transactions", headers=self.headers, json={"id": "transfer-1", "client_op_id": "device-1:3", "kind": "transfer", "amount": 50, "from_account_id": "bank", "to_account_id": "wallet", "occurred_on": "2026-09-02"})
        metrics = self.client.get("/stats?month=2026-09", headers=self.headers)
        self.assertEqual(metrics.status_code, 200, metrics.text)
        self.assertEqual(metrics.json()["income"], 100.0)
        self.assertEqual(metrics.json()["expense"], 41.0)
        backup = self.client.get("/backup/export", headers=self.headers)
        self.assertEqual(backup.status_code, 200, backup.text)
        self.assertGreaterEqual(len(backup.json()["transactions"]), 3)

    def test_sync_retry_returns_same_server_version(self):
        operation = {"client_op_id": "device-2:1", "entity": "transactions", "entity_id": "sync-tx", "type": "upsert", "payload": {"id": "sync-tx", "type": "expense", "amount": 9, "currency": "CNY", "account_id": "wallet", "occurred_on": "2026-09-03"}}
        first = self.client.post("/sync/push", headers=self.headers, json={"operations": [operation]})
        second = self.client.post("/sync/push", headers=self.headers, json={"operations": [operation]})
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        self.assertEqual(first.json()["accepted"][0]["server_version"], second.json()["accepted"][0]["server_version"])
        self.assertFalse(second.json()["accepted"][0]["created"])

    def test_verified_rate_is_snapshotted_and_report_numbers_are_programmatic(self):
        rate = self.client.post("/exchange/rates", headers=self.headers, json={"base_currency": "USD", "quote_currency": "CNY", "rate": 7.2, "rate_date": "2026-09-03", "source": "test verified source"})
        self.assertEqual(rate.status_code, 200, rate.text)
        tx = self.client.post("/transactions", headers=self.headers, json={"id": "usd-1", "client_op_id": "device-2:2", "kind": "expense", "amount": 10, "currency": "USD", "account_id": "wallet", "category_name": "交通", "occurred_on": "2026-09-03"})
        self.assertEqual(tx.status_code, 200, tx.text)
        self.assertEqual(tx.json()["cny_amount"], 72.0)
        report = self.client.get("/reports/monthly/2026-09?force=true", headers=self.headers)
        self.assertEqual(report.status_code, 200, report.text)
        self.assertEqual(report.json()["metrics"]["expense"], 113.0)
        self.assertIn("113", report.json()["summary"])
        self.assertIn(report.json()["ai_status"], ("unavailable", "success"))

    def test_v1_1_account_kind_and_transaction_time_survive_round_trip(self):
        account = self.client.post(
            "/accounts",
            headers=self.headers,
            json={"id": "fund-account", "name": "基金账户", "kind": "asset", "account_kind": "fund_investment"},
        )
        self.assertEqual(account.status_code, 200, account.text)
        self.assertEqual(account.json()["account_kind"], "fund_investment")

        transaction = self.client.post(
            "/transactions",
            headers=self.headers,
            json={
                "id": "timed-tx",
                "client_op_id": "contract:timed-tx",
                "kind": "expense",
                "amount": 12.5,
                "currency": "CNY",
                "account_id": "fund-account",
                "category_name": "测试",
                "occurred_on": "2030-01-03",
                "occurred_at": "2030-01-03T18:42:00+08:00",
            },
        )
        self.assertEqual(transaction.status_code, 200, transaction.text)
        self.assertEqual(transaction.json()["occurred_at"], "2030-01-03T18:42:00+08:00")

    def test_account_names_are_unique_within_one_user(self):
        first = self.client.post(
            "/accounts", headers=self.headers,
            json={"id": "unique-a", "name": "唯一账户", "kind": "asset"},
        )
        self.assertEqual(first.status_code, 200, first.text)
        duplicate = self.client.post(
            "/accounts", headers=self.headers,
            json={"id": "unique-b", "name": "唯一账户", "kind": "asset"},
        )
        self.assertEqual(duplicate.status_code, 409, duplicate.text)

    def test_v1_1_category_crud_keeps_archived_history_resolvable(self):
        created = self.client.post(
            "/categories",
            headers=self.headers,
            json={"id": "custom-category", "name": "宠物", "kind": "expense"},
        )
        self.assertEqual(created.status_code, 200, created.text)
        category_id = created.json()["id"]
        renamed = self.client.patch(
            f"/categories/{category_id}",
            headers=self.headers,
            json={"name": "宠物照护", "active": True},
        )
        self.assertEqual(renamed.status_code, 200, renamed.text)
        self.assertEqual(renamed.json()["id"], category_id)
        archived = self.client.post(f"/categories/{category_id}/archive", headers=self.headers)
        self.assertEqual(archived.status_code, 200, archived.text)
        listed = self.client.get("/categories", headers=self.headers)
        historical = next(item for item in listed.json()["items"] if item["id"] == category_id)
        self.assertFalse(historical["active"])

    def test_budget_create_update_and_month_filter_round_trip(self):
        created = self.client.post(
            "/budgets",
            headers=self.headers,
            json={"id": "food-budget-contract", "month": "2026-09", "category_id": "food", "limit": 800},
        )
        self.assertEqual(created.status_code, 200, created.text)
        self.assertEqual(created.json()["limit"], 800.0)

        updated = self.client.patch(
            "/budgets/food-budget-contract",
            headers=self.headers,
            json={"limit": 1200},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["limit"], 1200.0)

        listed = self.client.get("/budgets?month=2026-09", headers=self.headers)
        self.assertEqual(listed.status_code, 200, listed.text)
        self.assertEqual(listed.json()["items"][0]["limit"], 1200.0)

    def test_period_stats_return_zero_filled_daily_series_and_categories(self):
        self.client.post("/accounts", headers=self.headers, json={"id": "period-wallet", "name": "周期统计账户", "kind": "asset"})
        for suffix, day, amount, category in (
            ("a", "2027-01-01", 10, "餐饮"),
            ("b", "2027-01-03", 20, "交通"),
        ):
            response = self.client.post(
                "/transactions",
                headers=self.headers,
                json={
                    "id": f"period-{suffix}",
                    "client_op_id": f"contract:period-{suffix}",
                    "kind": "expense",
                    "amount": amount,
                    "currency": "CNY",
                    "account_id": "period-wallet",
                    "category_name": category,
                    "occurred_on": day,
                    "occurred_at": f"{day}T12:00:00+08:00",
                },
            )
            self.assertEqual(response.status_code, 200, response.text)
        response = self.client.get("/stats?period=week&start=2027-01-01&end=2027-01-07", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["period_start"], "2027-01-01")
        self.assertEqual(body["period_end"], "2027-01-07")
        self.assertEqual(len(body["expense_series"]), 7)
        self.assertEqual(body["expense_by_category"]["餐饮"], 10.0)
        self.assertEqual(body["expense_by_category"]["交通"], 20.0)

    def test_profile_can_update_display_name_and_username(self):
        response = self.client.get("/auth/me", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["username"], "test-user")

        changed = self.client.patch(
            "/auth/me",
            headers=self.headers,
            json={"display_name": "我的账本", "username": "test-user-renamed"},
        )
        self.assertEqual(changed.status_code, 200, changed.text)
        self.assertEqual(changed.json()["display_name"], "我的账本")
        self.assertEqual(changed.json()["username"], "test-user-renamed")
        self.__class__.headers = {"authorization": f"Bearer {changed.json()['access_token']}"}

        restored = self.client.patch(
            "/auth/me",
            headers=self.headers,
            json={"display_name": "财富用户", "username": "test-user"},
        )
        self.assertEqual(restored.status_code, 200, restored.text)
        self.__class__.headers = {"authorization": f"Bearer {restored.json()['access_token']}"}

    def test_password_change_requires_current_password_and_updates_login(self):
        rejected = self.client.post(
            "/auth/password",
            headers=self.headers,
            json={"current_password": "wrong", "new_password": "new-test-password"},
        )
        self.assertEqual(rejected.status_code, 401, rejected.text)

        changed = self.client.post(
            "/auth/password",
            headers=self.headers,
            json={"current_password": "test-password", "new_password": "new-test-password"},
        )
        self.assertEqual(changed.status_code, 200, changed.text)
        login = self.client.post(
            "/auth/login", json={"username": "test-user", "password": "new-test-password"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        old_login = self.client.post(
            "/auth/login", json={"username": "test-user", "password": "test-password"}
        )
        self.assertEqual(old_login.status_code, 401, old_login.text)

        restored = self.client.post(
            "/auth/password",
            headers={"authorization": f"Bearer {login.json()['access_token']}"},
            json={"current_password": "new-test-password", "new_password": "test-password"},
        )
        self.assertEqual(restored.status_code, 200, restored.text)
        self.__class__.headers = {"authorization": f"Bearer {restored.json()['access_token']}"}


if __name__ == "__main__":
    unittest.main()
