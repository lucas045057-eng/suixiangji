import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


class Sc08PayloadContractTest(unittest.TestCase):
    def test_flutter_account_transaction_batch_matches_sync_contract(self):
        """The exact Flutter Account → Transaction batch is accepted."""
        fd, db_path = tempfile.mkstemp(prefix="sc08-current-", suffix=".sqlite")
        os.close(fd)
        script = textwrap.dedent(
            r'''
            import json
            from fastapi.testclient import TestClient
            from app.main import app
            from app.db import SessionLocal, ensure_schema
            from app.models import Account, Category, SyncOperation, Transaction, User
            from app.security import create_token, hash_password

            ensure_schema()
            owner_id = "sc08-current-owner"
            account_id = "account-1788611638948235"
            transaction_id = "tx-1788611667068063"
            category_id = "d4446071-aee9-4dfa-b8ec-863f2e4c9b2d"
            db = SessionLocal()
            try:
                db.add(User(
                    id=owner_id,
                    username="sc08-current-owner",
                    password_hash=hash_password("sc08-password"),
                    display_name="SC08",
                ))
                db.add(Category(
                    id=category_id,
                    user_id=owner_id,
                    name="category",
                    kind="expense",
                    active=True,
                ))
                db.commit()
            finally:
                db.close()

            account = {
                "client_op_id": "account:account-1788611638948235:1788611638948235",
                "entity": "accounts",
                "entity_id": account_id,
                "type": "upsert",
                "payload": {
                    "id": account_id,
                    "name": "SC08-NEW-ACCOUNT",
                    "type": "asset",
                    "account_kind": "other",
                    "opening_balance": 0.0,
                    "currency": "CNY",
                    "opening_cny_amount": None,
                    "opening_exchange_rate": None,
                    "opening_rate_date": None,
                    "opening_rate_source": None,
                    "is_liquid": False,
                    "is_default_payment": False,
                    "deleted_at": None,
                    "server_version": None,
                    "updated_at": None,
                },
                "created_at": "2026-09-05T20:33:58.948235",
            }
            transaction = {
                "client_op_id": transaction_id,
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "date": "2026-09-05",
                    "occurred_at": "2026-09-05T00:00:00",
                    "type": "expense",
                    "amount": 8.9,
                    "currency": "CNY",
                    "original_amount": 8.9,
                    "original_currency": "CNY",
                    "cny_amount": None,
                    "exchange_rate": None,
                    "exchange_rate_date": None,
                    "exchange_rate_source": None,
                    "conversion_status": "ready",
                    "category_id": category_id,
                    "account_id": account_id,
                    "from_account_id": None,
                    "to_account_id": None,
                    "note": "SC08-ACCOUNT-DEPENDENCY-RERUN",
                    "client_op_id": transaction_id,
                    "server_version": None,
                    "updated_at": None,
                    "deleted_at": None,
                },
                "created_at": "2026-09-05T20:59:12.382835",
            }
            headers = {
                "authorization": "Bearer " + create_token(owner_id, "sc08-current-owner", 0)
            }
            with TestClient(app) as client:
                response = client.post(
                    "/sync/push",
                    headers=headers,
                    json={"operations": [account, transaction]},
                )
            db = SessionLocal()
            try:
                print(json.dumps({
                    "status": response.status_code,
                    "body": response.json(),
                    "account_rows": db.query(Account).filter(Account.id == account_id).count(),
                    "transaction_rows": db.query(Transaction).filter(Transaction.id == transaction_id).count(),
                    "sync_operation_rows": db.query(SyncOperation).count(),
                }, ensure_ascii=True))
            finally:
                db.close()
            '''
        )
        environment = os.environ.copy()
        environment["WEALTHMATE_DATABASE_URL"] = "sqlite:///" + Path(db_path).as_posix()
        environment["WEALTHMATE_JWT_SECRET"] = "sc08-current-secret"
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
            result = json.loads(stdout.strip().splitlines()[-1])
            self.assertEqual(result["status"], 200, output)
            self.assertEqual(result["account_rows"], 1, output)
            self.assertEqual(result["transaction_rows"], 1, output)
            self.assertEqual(result["sync_operation_rows"], 2, output)
        finally:
            try:
                Path(db_path).unlink()
            except PermissionError:
                pass


if __name__ == "__main__":
    unittest.main()
