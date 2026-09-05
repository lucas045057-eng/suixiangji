import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class ServerSeedVersionInvariantRedTest(unittest.TestCase):
    """Verify production initialization and version allocation semantics."""

    def _probe(self, mode: str) -> dict:
        fd, db_path = tempfile.mkstemp(prefix="seed-version-invariant-", suffix=".sqlite")
        os.close(fd)
        script = textwrap.dedent(
            r'''
            import json
            import os

            from fastapi.testclient import TestClient

            mode = os.environ["SEED_VERSION_INVARIANT_MODE"]
            if mode == "postgresql_style_login":
                from sqlalchemy import event
                from sqlalchemy.engine import Engine

                @event.listens_for(Engine, "connect")
                def _enable_sqlite_foreign_keys(dbapi_connection, _connection_record):
                    if dbapi_connection.__class__.__module__.startswith("sqlite3"):
                        cursor = dbapi_connection.cursor()
                        cursor.execute("PRAGMA foreign_keys=ON")
                        cursor.close()

            from app.main import app
            from app.db import SessionLocal
            from app.models import Account, Budget, Category, Transaction, User

            username = "seed-version-user"
            password = "seed-version-password"

            def rows(db):
                owner = db.query(User).filter(User.username == username).first()
                if owner is None:
                    return {
                        "user": None,
                        "accounts": [],
                        "categories": [],
                        "transactions": [],
                        "budgets": [],
                    }
                return {
                    "user": {
                        "id": owner.id,
                        "sync_version": owner.sync_version,
                    },
                    "accounts": [
                        {"id": row.id, "server_version": row.server_version}
                        for row in db.query(Account).filter(Account.user_id == owner.id).all()
                    ],
                    "categories": [
                        {"id": row.id, "server_version": row.server_version}
                        for row in db.query(Category).filter(Category.user_id == owner.id).all()
                    ],
                    "transactions": [
                        {"id": row.id, "server_version": row.server_version}
                        for row in db.query(Transaction).filter(Transaction.user_id == owner.id).all()
                    ],
                    "budgets": [
                        {"id": row.id, "server_version": row.server_version}
                        for row in db.query(Budget).filter(Budget.user_id == owner.id).all()
                    ],
                }

            result = {}
            with TestClient(app, raise_server_exceptions=False) as client:
                login = client.post(
                    "/auth/login",
                    json={"username": username, "password": password},
                )
                result["login_status"] = login.status_code
                try:
                    login_body = login.json()
                except ValueError:
                    login_body = {"detail": login.text}
                result["login_user_id"] = login_body.get("user_id")
                if login.status_code == 200:
                    headers = {"authorization": "Bearer " + login_body["access_token"]}

                    if mode == "normal_sequence" or mode == "incremental":
                        account = client.post(
                            "/accounts",
                            headers=headers,
                            json={"id": "normal-account", "name": "正常账户", "kind": "asset"},
                        )
                        category = client.post(
                            "/categories",
                            headers=headers,
                            json={"id": "normal-category", "name": "正常分类", "kind": "expense"},
                        )
                        transaction = client.post(
                            "/transactions",
                            headers=headers,
                            json={
                                "id": "normal-transaction",
                                "client_op_id": "normal-transaction-op",
                                "kind": "expense",
                                "amount": 12.34,
                                "currency": "CNY",
                                "account_id": "normal-account",
                                "category_id": "normal-category",
                                "occurred_on": "2026-09-05",
                            },
                        )
                        budget = client.post(
                            "/budgets",
                            headers=headers,
                            json={
                                "id": "normal-budget",
                                "month": "2026-09",
                                "category_id": "normal-category",
                                "limit": 500,
                            },
                        )
                        result["create_statuses"] = {
                            "account": account.status_code,
                            "category": category.status_code,
                            "transaction": transaction.status_code,
                            "budget": budget.status_code,
                        }
                        result["create_bodies"] = {
                            "account": account.json(),
                            "category": category.json(),
                            "transaction": transaction.json(),
                            "budget": budget.json(),
                        }

                    full_pull = client.get("/sync/pull?since_version=0", headers=headers)
                    result["full_pull_status"] = full_pull.status_code
                    result["full_pull_body"] = full_pull.json()

                    if mode == "incremental":
                        db = SessionLocal()
                        try:
                            owner = db.query(User).filter(User.username == username).one()
                            account_version = (
                                db.query(Account)
                                .filter(Account.user_id == owner.id, Account.id == "normal-account")
                                .one()
                                .server_version
                            )
                        finally:
                            db.close()
                        incremental = client.get(
                            f"/sync/pull?since_version={account_version}",
                            headers=headers,
                        )
                        result["incremental_since_version"] = account_version
                        result["incremental_pull_status"] = incremental.status_code
                        result["incremental_pull_body"] = incremental.json()

            db = SessionLocal()
            try:
                result["db"] = rows(db)
            finally:
                db.close()
            print(json.dumps(result, ensure_ascii=True))
            '''
        )
        environment = os.environ.copy()
        environment["WEALTHMATE_DATABASE_URL"] = "sqlite:///" + Path(db_path).as_posix()
        environment["WEALTHMATE_DEMO_USERNAME"] = "seed-version-user"
        environment["WEALTHMATE_DEMO_PASSWORD"] = "seed-version-password"
        environment["WEALTHMATE_JWT_SECRET"] = "seed-version-secret"
        environment["SEED_VERSION_INVARIANT_MODE"] = mode
        try:
            completed = subprocess.run(
                [sys.executable, "-X", "utf8", "-"],
                input=("# -*- coding: utf-8 -*-\n" + script).encode("utf-8"),
                cwd=Path(__file__).resolve().parents[1],
                env=environment,
                capture_output=True,
                check=False,
            )
            stdout = completed.stdout.decode("utf-8", errors="replace")
            stderr = completed.stderr.decode("utf-8", errors="replace")
            output = (stdout + stderr).strip()
            self.assertEqual(completed.returncode, 0, output)
            return json.loads(stdout.strip().splitlines()[-1])
        finally:
            try:
                Path(db_path).unlink()
            except PermissionError:
                pass

    def test_fresh_client_receives_initial_account(self):
        result = self._probe("normal_sequence")
        actual = json.dumps(result, ensure_ascii=False)

        self.assertEqual(result["login_status"], 200, actual)
        self.assertEqual(result["full_pull_status"], 200, actual)
        self.assertTrue(
            any(item["id"] == "normal-account" for item in result["full_pull_body"]["accounts"]),
            actual,
        )

    def test_fresh_client_receives_initial_category(self):
        result = self._probe("login_bootstrap")
        actual = json.dumps(result, ensure_ascii=False)

        self.assertEqual(result["login_status"], 200, actual)
        self.assertEqual(result["full_pull_status"], 200, actual)
        self.assertGreater(len(result["full_pull_body"]["categories"]), 0, actual)

    def test_default_category_initialization_respects_database_foreign_keys(self):
        result = self._probe("postgresql_style_login")
        actual = json.dumps(result, ensure_ascii=False)

        self.assertEqual(result["login_status"], 200, actual)
        self.assertEqual(result["full_pull_status"], 200, actual)

    def test_initial_entities_have_positive_server_versions(self):
        result = self._probe("login_bootstrap")
        actual = json.dumps(result, ensure_ascii=False)

        self.assertGreater(result["db"]["user"]["sync_version"], 0, actual)
        self.assertTrue(
            all(item["server_version"] > 0 for item in result["db"]["categories"]),
            actual,
        )
        category_versions = [item["server_version"] for item in result["db"]["categories"]]
        self.assertGreaterEqual(result["db"]["user"]["sync_version"], max(category_versions), actual)

    def test_server_version_sequence_is_monotonic(self):
        result = self._probe("normal_sequence")
        actual = json.dumps(result, ensure_ascii=False)

        self.assertEqual(result["create_statuses"], {"account": 200, "category": 200, "transaction": 200, "budget": 200}, actual)
        versions = [
            next(item["server_version"] for item in result["db"]["accounts"] if item["id"] == "normal-account"),
            next(item["server_version"] for item in result["db"]["categories"] if item["id"] == "normal-category"),
            next(item["server_version"] for item in result["db"]["transactions"] if item["id"] == "normal-transaction"),
            next(item["server_version"] for item in result["db"]["budgets"] if item["id"] == "normal-budget"),
        ]
        self.assertEqual(versions, sorted(versions), actual)
        self.assertEqual(len(set(versions)), len(versions), actual)
        self.assertEqual(result["db"]["user"]["sync_version"], versions[-1], actual)

    def test_incremental_pull_uses_strictly_greater_server_version(self):
        result = self._probe("incremental")
        actual = json.dumps(result, ensure_ascii=False)
        incremental = result["incremental_pull_body"]

        self.assertEqual(result["incremental_pull_status"], 200, actual)
        self.assertFalse(any(item["id"] == "normal-account" for item in incremental["accounts"]), actual)
        self.assertTrue(any(item["id"] == "normal-category" for item in incremental["categories"]), actual)
        self.assertTrue(any(item["id"] == "normal-transaction" for item in incremental["transactions"]), actual)
        self.assertTrue(any(item["id"] == "normal-budget" for item in incremental["budgets"]), actual)


if __name__ == "__main__":
    unittest.main()
