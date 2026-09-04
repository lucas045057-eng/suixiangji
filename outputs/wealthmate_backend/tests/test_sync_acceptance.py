class SyncAcceptanceMixin:
    def _prepare_sync_fixtures(self):
        from app.db import SessionLocal
        from app.models import User
        from app.security import create_token, hash_password

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").first()
            if not owner:
                owner = User(
                    id="sync-acceptance-owner-id",
                    username="sync-acceptance-owner",
                    password_hash=hash_password("sync-password"),
                    display_name="同步测试用户",
                )
                db.add(owner)
                db.commit()
                db.refresh(owner)
            self.sync_headers = {
                "authorization": f"Bearer {create_token(owner.id, owner.username, owner.auth_version or 0)}"
            }
        finally:
            db.close()
        account = self.client.post(
            "/accounts",
            headers=self.sync_headers,
            json={"id": "sync-acceptance-wallet", "name": "同步测试钱包", "kind": "asset"},
        )
        self.assertIn(account.status_code, (200, 409), account.text)
        category = self.client.post(
            "/categories",
            headers=self.sync_headers,
            json={"id": "sync-acceptance-food", "name": "同步测试餐饮", "kind": "expense"},
        )
        self.assertIn(category.status_code, (200, 409), category.text)
        db = SessionLocal()
        try:
            if not db.query(User).filter(User.username == "sync-acceptance-other").first():
                db.add(
                    User(
                        id="sync-acceptance-other-id",
                        username="sync-acceptance-other",
                        password_hash=hash_password("sync-password"),
                        display_name="同步测试其他用户",
                    )
                )
                db.commit()
        finally:
            db.close()

    def _operation(self, suffix, *, amount=1, note="初始"):
        return {
            "client_op_id": f"sync-acceptance:{suffix}",
            "entity": "transactions",
            "entity_id": f"sync-acceptance-tx-{suffix}",
            "type": "upsert",
            "payload": {
                "id": f"sync-acceptance-tx-{suffix}",
                "type": "expense",
                "amount": amount,
                "currency": "CNY",
                "account_id": "sync-acceptance-wallet",
                "category_id": "sync-acceptance-food",
                "occurred_on": "2026-09-04",
                "note": note,
            },
        }

    def test_sync_01_online_create_round_trips_required_fields(self):
        self._prepare_sync_fixtures()
        operation = self._operation("online", amount=23, note="在线新增")
        pushed = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        self.assertEqual(pushed.status_code, 200, pushed.text)
        self.assertEqual(len(pushed.json()["accepted"]), 1)
        self.assertGreater(pushed.json()["accepted"][0]["server_version"], 0)
        pulled = self.client.get("/sync/pull?since_version=0", headers=self.sync_headers)
        self.assertEqual(pulled.status_code, 200, pulled.text)
        row = next(
            item
            for item in pulled.json()["transactions"]
            if item["id"] == "sync-acceptance-tx-online"
        )
        self.assertEqual(row["client_op_id"], operation["client_op_id"])
        self.assertEqual(row["amount"], 23.0)
        self.assertEqual(row["category_id"], "sync-acceptance-food")
        self.assertEqual(row["account_id"], "sync-acceptance-wallet")
        self.assertEqual(row["occurred_on"], "2026-09-04")

    def test_sync_02_ten_offline_operations_are_idempotent(self):
        self._prepare_sync_fixtures()
        operations = [self._operation(f"ten-{index}", amount=index + 1) for index in range(10)]
        first = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(len(first.json()["accepted"]), 10)

        second = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )
        self.assertEqual(second.status_code, 200, second.text)
        self.assertTrue(all(not item["created"] for item in second.json()["accepted"]))
        rows = self.client.get("/transactions", headers=self.sync_headers).json()["items"]
        self.assertEqual(
            len([row for row in rows if row["client_op_id"].startswith("sync-acceptance:ten-")]),
            10,
        )

    def test_sync_03_offline_update_preserves_latest_server_state(self):
        self._prepare_sync_fixtures()
        created = self.client.post(
            "/sync/push",
            headers=self.sync_headers,
            json={"operations": [self._operation("update", amount=10)]},
        )
        self.assertEqual(created.status_code, 200, created.text)
        version = created.json()["accepted"][0]["server_version"]
        update = self._operation("update-replay", amount=18, note="离线修改")
        update["entity_id"] = "sync-acceptance-tx-update"
        update["payload"]["id"] = "sync-acceptance-tx-update"
        update["payload"]["server_version"] = version

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [update]}
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse(response.json()["conflicts"])
        row = next(
            item
            for item in self.client.get("/transactions", headers=self.sync_headers).json()["items"]
            if item["id"] == "sync-acceptance-tx-update"
        )
        self.assertEqual(row["amount"], 18.0)
        self.assertEqual(row["note"], "离线修改")
        self.assertGreater(row["server_version"], version)

    def test_sync_04_offline_delete_is_a_server_soft_delete(self):
        self._prepare_sync_fixtures()
        created = self.client.post(
            "/sync/push",
            headers=self.sync_headers,
            json={"operations": [self._operation("delete", amount=11)]},
        )
        self.assertEqual(created.status_code, 200, created.text)
        version = created.json()["accepted"][0]["server_version"]
        delete = self._operation("delete-tombstone", amount=11)
        delete["entity_id"] = "sync-acceptance-tx-delete"
        delete["payload"]["id"] = "sync-acceptance-tx-delete"
        delete["payload"]["server_version"] = version
        delete["type"] = "delete"

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [delete]}
        )
        self.assertEqual(response.status_code, 200, response.text)
        visible = self.client.get("/transactions", headers=self.sync_headers).json()["items"]
        self.assertFalse(any(item["id"] == "sync-acceptance-tx-delete" for item in visible))
        all_rows = self.client.get(
            "/transactions?include_deleted=true", headers=self.sync_headers
        ).json()["items"]
        tombstone = next(item for item in all_rows if item["id"] == "sync-acceptance-tx-delete")
        self.assertIsNotNone(tombstone["deleted_at"])

    def test_sync_05_same_client_operation_has_one_business_result(self):
        self._prepare_sync_fixtures()
        operation = self._operation("idempotent", amount=32)
        first = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )
        second = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(second.status_code, 200, second.text)
        self.assertEqual(
            first.json()["accepted"][0]["server_version"],
            second.json()["accepted"][0]["server_version"],
        )
        rows = self.client.get("/transactions", headers=self.sync_headers).json()["items"]
        self.assertEqual(
            len([row for row in rows if row["client_op_id"] == operation["client_op_id"]]),
            1,
        )

    def test_sync_07_empty_client_can_full_pull_all_supported_entities(self):
        self._prepare_sync_fixtures()
        account = self.client.post(
            "/accounts",
            headers=self.sync_headers,
            json={"id": "sync-acceptance-full-account", "name": "全量恢复账户", "kind": "asset"},
        )
        self.assertEqual(account.status_code, 200, account.text)
        category = self.client.post(
            "/categories",
            headers=self.sync_headers,
            json={"id": "sync-acceptance-full-category", "name": "全量恢复分类", "kind": "expense"},
        )
        self.assertEqual(category.status_code, 200, category.text)
        transaction = self.client.post(
            "/transactions",
            headers=self.sync_headers,
            json={
                "id": "sync-acceptance-full-transaction",
                "client_op_id": "sync-acceptance:full-transaction",
                "kind": "expense",
                "amount": 8,
                "currency": "CNY",
                "account_id": "sync-acceptance-full-account",
                "category_id": "sync-acceptance-full-category",
                "occurred_on": "2026-09-04",
            },
        )
        self.assertEqual(transaction.status_code, 200, transaction.text)
        budget = self.client.post(
            "/budgets",
            headers=self.sync_headers,
            json={
                "id": "sync-acceptance-full-budget",
                "month": "2026-09",
                "category_id": "sync-acceptance-full-category",
                "limit": 500,
            },
        )
        self.assertEqual(budget.status_code, 200, budget.text)

        full_pull = self.client.get("/sync/pull?since_version=0", headers=self.sync_headers)
        self.assertEqual(full_pull.status_code, 200, full_pull.text)
        body = full_pull.json()
        self.assertTrue(any(item["id"] == account.json()["id"] for item in body["accounts"]))
        self.assertTrue(any(item["id"] == category.json()["id"] for item in body["categories"]))
        self.assertTrue(any(item["id"] == transaction.json()["id"] for item in body["transactions"]))
        self.assertTrue(any(item["id"] == budget.json()["id"] for item in body["budgets"]))

    def test_sync_cross_user_cannot_read_or_mutate_another_users_data(self):
        self._prepare_sync_fixtures()
        owner_tx = self._operation("cross-user", amount=77)
        created = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [owner_tx]}
        )
        self.assertEqual(created.status_code, 200, created.text)

        other_login = self.client.post(
            "/auth/login",
            json={"username": "sync-acceptance-other", "password": "sync-password"},
        )
        self.assertEqual(other_login.status_code, 200, other_login.text)
        other_headers = {"authorization": f"Bearer {other_login.json()['access_token']}"}
        self.assertEqual(
            self.client.get("/sync/pull?since_version=0", headers=other_headers).json()["transactions"],
            [],
        )
        self.assertEqual(
            self.client.delete(
                "/transactions/sync-acceptance-tx-cross-user", headers=other_headers
            ).status_code,
            404,
        )
        foreign_update = owner_tx.copy()
        foreign_update["client_op_id"] = "sync-acceptance:cross-user-attack"
        self.assertEqual(
            self.client.post(
                "/sync/push", headers=other_headers, json={"operations": [foreign_update]}
            ).status_code,
            404,
        )
