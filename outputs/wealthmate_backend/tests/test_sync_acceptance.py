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

    def test_sync_push_handles_account_dependency_when_transaction_precedes_account(self):
        """A batch must not depend on the incidental operation order."""
        from app.db import SessionLocal
        from app.models import Account, Transaction, User

        self._prepare_sync_fixtures()
        transaction_id = "sync-dependency-tx-001"
        account_id = "new-alipay"
        operations = [
            {
                "client_op_id": "tx-op-001",
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "type": "expense",
                    "amount": 1.23,
                    "currency": "CNY",
                    "account_id": account_id,
                    "category_id": "sync-acceptance-food",
                    "occurred_on": "2026-09-05",
                    "note": "依赖顺序 RED",
                },
            },
            {
                "client_op_id": "account-op-001",
                "entity": "accounts",
                "entity_id": account_id,
                "type": "upsert",
                "payload": {
                    "id": account_id,
                    "name": "测试支付宝",
                    "kind": "asset",
                },
            },
        ]

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Account, account_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )

        db = SessionLocal()
        try:
            account_rows = (
                db.query(Account)
                .filter(Account.user_id == owner.id, Account.id == account_id)
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"account_rows={len(account_rows)}; transaction_rows={len(transaction_rows)}"
        )
        self.assertEqual(response.status_code, 200, actual)
        accepted = response.json()["accepted"]
        self.assertEqual(
            [item["client_op_id"] for item in accepted],
            ["tx-op-001", "account-op-001"],
            actual,
        )
        self.assertEqual(
            [item["entity_id"] for item in accepted],
            [transaction_id, account_id],
            actual,
        )
        self.assertEqual(len(account_rows), 1, actual)
        self.assertEqual(len(transaction_rows), 1, actual)
        self.assertEqual(transaction_rows[0].account_id, account_id, actual)

        repeated = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )
        self.assertEqual(repeated.status_code, 200, repeated.text)
        self.assertTrue(all(not item["created"] for item in repeated.json()["accepted"]))
        db = SessionLocal()
        try:
            self.assertEqual(
                db.query(Account)
                .filter(Account.user_id == owner.id, Account.id == account_id)
                .count(),
                1,
            )
            self.assertEqual(
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .count(),
                1,
            )
        finally:
            db.close()

    def test_sync_push_accepts_account_before_transaction(self):
        from app.db import SessionLocal
        from app.models import Account, Transaction, User

        self._prepare_sync_fixtures()
        transaction_id = "sync-normal-order-tx-001"
        account_id = "normal-alipay"
        operations = [
            {
                "client_op_id": "normal-account-op-001",
                "entity": "accounts",
                "entity_id": account_id,
                "type": "upsert",
                "payload": {"id": account_id, "name": "正常顺序支付宝", "kind": "asset"},
            },
            {
                "client_op_id": "normal-tx-op-001",
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "type": "expense",
                    "amount": 1.23,
                    "currency": "CNY",
                    "account_id": account_id,
                    "category_id": "sync-acceptance-food",
                    "occurred_on": "2026-09-05",
                    "note": "正常顺序",
                },
            },
        ]

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(
            [item["client_op_id"] for item in response.json()["accepted"]],
            ["normal-account-op-001", "normal-tx-op-001"],
        )

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertEqual(
                db.query(Account)
                .filter(Account.user_id == owner.id, Account.id == account_id)
                .count(),
                1,
            )
            row = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .one()
            )
            self.assertEqual(row.account_id, account_id)
        finally:
            db.close()

    def test_sync_push_handles_category_dependency_when_transaction_precedes_category(self):
        from app.db import SessionLocal
        from app.models import Category, Transaction, User

        self._prepare_sync_fixtures()
        transaction_id = "sync-category-dependency-tx-001"
        category_id = "new-food"
        operations = [
            {
                "client_op_id": "category-tx-op-001",
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "type": "expense",
                    "amount": 4.56,
                    "currency": "CNY",
                    "account_id": "sync-acceptance-wallet",
                    "category_id": category_id,
                    "occurred_on": "2026-09-05",
                    "note": "分类依赖",
                },
            },
            {
                "client_op_id": "category-op-001",
                "entity": "categories",
                "entity_id": category_id,
                "type": "upsert",
                "payload": {
                    "id": category_id,
                    "name": "测试餐饮分类",
                    "kind": "expense",
                },
            },
        ]

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Category, category_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )

        db = SessionLocal()
        try:
            category_rows = (
                db.query(Category)
                .filter(Category.user_id == owner.id, Category.id == category_id)
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"category_rows={len(category_rows)}; transaction_rows={len(transaction_rows)}"
        )
        self.assertEqual(response.status_code, 200, actual)
        self.assertEqual(
            [item["client_op_id"] for item in response.json()["accepted"]],
            ["category-tx-op-001", "category-op-001"],
            actual,
        )
        self.assertEqual(len(category_rows), 1, actual)
        self.assertEqual(len(transaction_rows), 1, actual)
        self.assertEqual(transaction_rows[0].category_id, category_id, actual)

        repeated = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )
        self.assertEqual(repeated.status_code, 200, repeated.text)
        self.assertTrue(all(not item["created"] for item in repeated.json()["accepted"]))
        db = SessionLocal()
        try:
            self.assertEqual(
                db.query(Category)
                .filter(Category.user_id == owner.id, Category.id == category_id)
                .count(),
                1,
            )
            self.assertEqual(
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .count(),
                1,
            )
        finally:
            db.close()

    def test_sync_push_handles_category_dependency_when_budget_precedes_category(self):
        from app.db import SessionLocal
        from app.models import Budget, Category, User

        self._prepare_sync_fixtures()
        budget_id = "sync-budget-dependency-001"
        category_id = "new-budget-category"
        operations = [
            {
                "client_op_id": "budget-op-001",
                "entity": "budgets",
                "entity_id": budget_id,
                "type": "upsert",
                "payload": {
                    "id": budget_id,
                    "month": "2026-09",
                    "category_id": category_id,
                    "limit": 500,
                },
            },
            {
                "client_op_id": "budget-category-op-001",
                "entity": "categories",
                "entity_id": category_id,
                "type": "upsert",
                "payload": {
                    "id": category_id,
                    "name": "测试预算分类",
                    "kind": "expense",
                },
            },
        ]

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Category, category_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )

        db = SessionLocal()
        try:
            category_rows = (
                db.query(Category)
                .filter(Category.user_id == owner.id, Category.id == category_id)
                .all()
            )
            budget_rows = (
                db.query(Budget)
                .filter(Budget.user_id == owner.id, Budget.id == budget_id)
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"category_rows={len(category_rows)}; budget_rows={len(budget_rows)}"
        )
        self.assertEqual(response.status_code, 200, actual)
        self.assertEqual(
            [item["client_op_id"] for item in response.json()["accepted"]],
            ["budget-op-001", "budget-category-op-001"],
            actual,
        )
        self.assertEqual(len(category_rows), 1, actual)
        self.assertEqual(len(budget_rows), 1, actual)
        self.assertEqual(budget_rows[0].category_id, category_id, actual)

    def test_sync_rejects_budget_with_truly_missing_category(self):
        from app.db import SessionLocal
        from app.models import Budget, Category, User

        self._prepare_sync_fixtures()
        budget_id = "sync-missing-budget-category-001"
        category_id = "missing-budget-category"
        operation = {
            "client_op_id": "missing-budget-category-op-001",
            "entity": "budgets",
            "entity_id": budget_id,
            "type": "upsert",
            "payload": {
                "id": budget_id,
                "month": "2026-09",
                "category_id": category_id,
                "limit": 500,
            },
        }

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Category, category_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        db = SessionLocal()
        try:
            category_rows = (
                db.query(Category)
                .filter(Category.user_id == owner.id, Category.id == category_id)
                .all()
            )
            budget_rows = (
                db.query(Budget)
                .filter(Budget.user_id == owner.id, Budget.id == budget_id)
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"category_rows={len(category_rows)}; budget_rows={len(budget_rows)}"
        )
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertEqual(category_rows, [], actual)
        self.assertEqual(budget_rows, [], actual)

    def test_sync_rejects_budget_using_another_users_category(self):
        from app.db import SessionLocal
        from app.models import Budget, Category, User
        from app.security import hash_password

        self._prepare_sync_fixtures()
        budget_id = "sync-foreign-budget-category-001"
        category_id = "foreign-budget-category"
        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            foreign_owner = db.query(User).filter(User.username == "sync-budget-foreign-owner").first()
            if not foreign_owner:
                foreign_owner = User(
                    id="sync-budget-foreign-owner-id",
                    username="sync-budget-foreign-owner",
                    password_hash=hash_password("sync-password"),
                    display_name="预算归属测试用户",
                )
                db.add(foreign_owner)
                db.flush()
            category = db.get(Category, category_id)
            if not category:
                category = Category(
                    id=category_id,
                    user_id=foreign_owner.id,
                    name="User B 预算分类",
                    kind="expense",
                )
                db.add(category)
                db.commit()
            self.assertEqual(category.user_id, foreign_owner.id)
            self.assertNotEqual(category.user_id, owner.id)
        finally:
            db.close()

        operation = {
            "client_op_id": "foreign-budget-category-op-001",
            "entity": "budgets",
            "entity_id": budget_id,
            "type": "upsert",
            "payload": {
                "id": budget_id,
                "month": "2026-09",
                "category_id": category_id,
                "limit": 500,
            },
        }
        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        db = SessionLocal()
        try:
            budget_rows = (
                db.query(Budget)
                .filter(Budget.user_id == owner.id, Budget.id == budget_id)
                .all()
            )
        finally:
            db.close()

        actual = f"HTTP status={response.status_code}; body={response.text}; budget_rows={len(budget_rows)}"
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertEqual(budget_rows, [], actual)

    def test_sync_push_rolls_back_entire_batch_when_later_operation_fails(self):
        from app.db import SessionLocal
        from app.models import Account, SyncOperation, Transaction, User

        self._prepare_sync_fixtures()
        account_id = "atomic-account-001"
        transaction_id = "atomic-tx-001"
        account_op_id = "atomic-account-op-001"
        transaction_op_id = "atomic-tx-op-001"
        operations = [
            {
                "client_op_id": account_op_id,
                "entity": "accounts",
                "entity_id": account_id,
                "type": "upsert",
                "payload": {
                    "id": account_id,
                    "name": "原子性测试账户",
                    "kind": "asset",
                },
            },
            {
                "client_op_id": transaction_op_id,
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "type": "expense",
                    "amount": 9.99,
                    "currency": "CNY",
                    "account_id": "definitely-missing-account",
                    "category_id": "sync-acceptance-food",
                    "occurred_on": "2026-09-05",
                },
            },
        ]

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            owner_id = owner.id
            version_before = owner.sync_version
            self.assertIsNone(db.get(Account, account_id))
            self.assertIsNone(db.get(Transaction, transaction_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )

        db = SessionLocal()
        try:
            account_rows = (
                db.query(Account)
                .filter(Account.user_id == owner_id, Account.id == account_id)
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner_id, Transaction.id == transaction_id)
                .all()
            )
            sync_operations = (
                db.query(SyncOperation)
                .filter(
                    SyncOperation.user_id == owner_id,
                    SyncOperation.client_op_id.in_([account_op_id, transaction_op_id]),
                )
                .all()
            )
            owner_after = db.get(User, owner_id)
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"account_rows={len(account_rows)}; transaction_rows={len(transaction_rows)}; "
            f"sync_operations={len(sync_operations)}; "
            f"sync_version_before={version_before}; sync_version_after={owner_after.sync_version}"
        )
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertIn("账户不存在: definitely-missing-account", response.text, actual)
        self.assertEqual(account_rows, [], actual)
        self.assertEqual(transaction_rows, [], actual)
        self.assertEqual(sync_operations, [], actual)
        self.assertEqual(owner_after.sync_version, version_before, actual)

    def test_sync_push_does_not_apply_operations_after_a_failed_operation(self):
        from app.db import SessionLocal
        from app.models import Account, SyncOperation, Transaction, User

        self._prepare_sync_fixtures()
        account_id = "atomic-account-002"
        transaction_id = "atomic-tx-002"
        account_op_id = "atomic-account-op-002"
        transaction_op_id = "atomic-tx-op-002"
        operations = [
            {
                "client_op_id": transaction_op_id,
                "entity": "transactions",
                "entity_id": transaction_id,
                "type": "upsert",
                "payload": {
                    "id": transaction_id,
                    "type": "expense",
                    "amount": 9.99,
                    "currency": "CNY",
                    "account_id": "definitely-missing-account-002",
                    "category_id": "sync-acceptance-food",
                    "occurred_on": "2026-09-05",
                },
            },
            {
                "client_op_id": account_op_id,
                "entity": "accounts",
                "entity_id": account_id,
                "type": "upsert",
                "payload": {
                    "id": account_id,
                    "name": "失败后续账户",
                    "kind": "asset",
                },
            },
        ]

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            owner_id = owner.id
            self.assertIsNone(db.get(Account, account_id))
            self.assertIsNone(db.get(Transaction, transaction_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": operations}
        )

        db = SessionLocal()
        try:
            account_rows = (
                db.query(Account)
                .filter(Account.user_id == owner_id, Account.id == account_id)
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner_id, Transaction.id == transaction_id)
                .all()
            )
            sync_operations = (
                db.query(SyncOperation)
                .filter(
                    SyncOperation.user_id == owner_id,
                    SyncOperation.client_op_id.in_([account_op_id, transaction_op_id]),
                )
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"account_rows={len(account_rows)}; transaction_rows={len(transaction_rows)}; "
            f"sync_operations={len(sync_operations)}"
        )
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertIn("账户不存在: definitely-missing-account-002", response.text, actual)
        self.assertEqual(account_rows, [], actual)
        self.assertEqual(transaction_rows, [], actual)
        self.assertEqual(sync_operations, [], actual)

    def test_sync_rejects_transaction_with_truly_missing_category(self):
        from app.db import SessionLocal
        from app.models import Category, Transaction, User

        self._prepare_sync_fixtures()
        transaction_id = "sync-missing-category-tx-001"
        category_id = "missing-category"
        operation = self._operation("missing-category", amount=4.56, note="缺失分类保护")
        operation["entity_id"] = transaction_id
        operation["payload"]["id"] = transaction_id
        operation["payload"]["category_id"] = category_id

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Category, category_id))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        db = SessionLocal()
        try:
            category_rows = (
                db.query(Category)
                .filter(Category.user_id == owner.id, Category.id == category_id)
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .all()
            )
        finally:
            db.close()

        actual = (
            f"HTTP status={response.status_code}; body={response.text}; "
            f"category_rows={len(category_rows)}; transaction_rows={len(transaction_rows)}"
        )
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertIn("分类不存在: missing-category", response.text, actual)
        self.assertEqual(category_rows, [], actual)
        self.assertEqual(transaction_rows, [], actual)

    def test_sync_rejects_transaction_using_another_users_category(self):
        from app.db import SessionLocal
        from app.models import Category, Transaction, User
        from app.security import hash_password

        self._prepare_sync_fixtures()
        category_id = "foreign-category"
        transaction_id = "sync-foreign-category-tx-001"
        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            foreign_owner = db.query(User).filter(User.username == "sync-category-foreign-owner").first()
            if not foreign_owner:
                foreign_owner = User(
                    id="sync-category-foreign-owner-id",
                    username="sync-category-foreign-owner",
                    password_hash=hash_password("sync-password"),
                    display_name="分类归属测试用户",
                )
                db.add(foreign_owner)
                db.flush()
            category = db.get(Category, category_id)
            if not category:
                category = Category(
                    id=category_id,
                    user_id=foreign_owner.id,
                    name="User B 分类",
                    kind="expense",
                )
                db.add(category)
                db.commit()
            self.assertEqual(category.user_id, foreign_owner.id)
            self.assertNotEqual(category.user_id, owner.id)
        finally:
            db.close()

        operation = self._operation("foreign-category", amount=7.89, note="跨用户分类保护")
        operation["entity_id"] = transaction_id
        operation["payload"]["id"] = transaction_id
        operation["payload"]["category_id"] = category_id
        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        db = SessionLocal()
        try:
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .all()
            )
        finally:
            db.close()

        actual = f"HTTP status={response.status_code}; body={response.text}; transaction_rows={len(transaction_rows)}"
        self.assertGreaterEqual(response.status_code, 400, actual)
        self.assertLess(response.status_code, 500, actual)
        self.assertEqual(transaction_rows, [], actual)

    def test_sync_rejects_transaction_with_truly_missing_account(self):
        from app.db import SessionLocal
        from app.models import Account, Transaction, User

        self._prepare_sync_fixtures()
        transaction_id = "sync-missing-account-tx-001"
        operation = self._operation("missing-account", amount=1.23, note="缺失账户保护")
        operation["entity_id"] = transaction_id
        operation["payload"]["id"] = transaction_id
        operation["payload"]["account_id"] = "missing-account"

        db = SessionLocal()
        try:
            owner = db.query(User).filter(User.username == "sync-acceptance-owner").one()
            self.assertIsNone(db.get(Account, "missing-account"))
        finally:
            db.close()

        response = self.client.post(
            "/sync/push", headers=self.sync_headers, json={"operations": [operation]}
        )

        db = SessionLocal()
        try:
            account_rows = (
                db.query(Account)
                .filter(Account.user_id == owner.id, Account.id == "missing-account")
                .all()
            )
            transaction_rows = (
                db.query(Transaction)
                .filter(Transaction.user_id == owner.id, Transaction.id == transaction_id)
                .all()
            )
        finally:
            db.close()

        self.assertGreaterEqual(response.status_code, 400, response.text)
        self.assertLess(response.status_code, 500, response.text)
        self.assertIn("账户不存在: missing-account", response.text)
        self.assertEqual(account_rows, [])
        self.assertEqual(transaction_rows, [])

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
