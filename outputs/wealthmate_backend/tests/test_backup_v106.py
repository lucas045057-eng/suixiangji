from __future__ import annotations

import pytest
from sqlalchemy import select

from test_user_system import headers, invite, register
from app.auth.registration import DEFAULT_CATEGORIES


pytest_plugins = ["test_user_system"]


def _user(api, username="backup-user"):
    client, sessions = api
    invite(sessions)
    response = register(client, username, display_name="Original profile")
    return client, sessions, headers(response)


def _restore_payload(*, owner_id=None, restore_id="restore-test-1"):
    payload = {
        "kind": "suixiangji.backup",
        "schema_version": 2,
        "owner_id": owner_id,
        "profile": {
            "display_name": "Restored profile",
            "quick_memories": [{"text": "保存发票"}],
        },
        "accounts": [
            {
                "id": "restore-account",
                "name": "Restored account",
                "kind": "asset",
                "account_kind": "bank_card",
                "currency": "CNY",
                "opening_balance": "100.000000",
                "opening_cny_amount": "100.000000",
                "opening_exchange_rate": "1.0000000000",
                "opening_rate_date": "2026-09-01",
                "opening_rate_source": "backup",
                "is_liquid": True,
                "is_default_payment": False,
                "archived_at": None,
                "deleted_at": None,
                "server_version": 999,
                "updated_at": "2099-01-01T00:00:00",
            }
        ],
        "categories": [
            {
                "id": "restore-category",
                "name": "Restored category",
                "kind": "expense",
                "active": False,
                "server_version": 998,
            }
        ],
        "budgets": [
            {
                "id": "restore-budget",
                "month": "2026-09",
                "category_id": "restore-category",
                "limit": "1234.560000",
                "active": False,
                "deleted_at": "2026-09-20T10:00:00+00:00",
                "server_version": 997,
            }
        ],
        "transactions": [
            {
                "id": "restore-transaction",
                "client_op_id": "restore-tx-op",
                "kind": "expense",
                "amount": "12.345678",
                "currency": "CNY",
                "cny_amount": "12.345678",
                "exchange_rate": "1.0000000000",
                "exchange_rate_date": "2026-09-01",
                "exchange_rate_source": "backup",
                "conversion_status": "ready",
                "category_id": "restore-category",
                "account_id": "restore-account",
                "occurred_on": "2026-09-02",
                "occurred_at": "2026-09-02T12:00:00+08:00",
                "note": "restored",
                "deleted_at": "2026-09-21T10:00:00+00:00",
                "server_version": 996,
                "updated_at": "2099-01-01T00:00:00",
            }
        ],
        "source_server_version": 999,
        "exported_at": "2099-01-01T00:00:00+00:00",
        "restore_id": restore_id,
    }
    if owner_id is None:
        payload.pop("owner_id")
    return payload


def test_v2_export_contains_core_entities_profile_tombstones_and_decimal_strings(api):
    client, sessions, auth = _user(api)
    assert client.post(
        "/accounts", headers=auth,
        json={"id": "export-account", "name": "Export account", "opening_balance": "10.125678"},
    ).status_code == 200
    category = client.post(
        "/categories", headers=auth,
        json={"id": "export-category", "name": "Export category", "kind": "expense"},
    )
    assert category.status_code == 200, category.text
    assert client.post(
        "/budgets", headers=auth,
        json={"id": "export-budget", "category_id": "export-category", "month": "2026-09", "limit": "20.125678"},
    ).status_code == 200
    assert client.post(
        "/transactions", headers=auth,
        json={"id": "export-tx", "client_op_id": "export-op", "kind": "expense", "amount": "2.125678", "account_id": "export-account", "category_id": "export-category", "occurred_on": "2026-09-01"},
    ).status_code == 200
    assert client.post("/categories/export-category/archive", headers=auth).status_code == 200
    assert client.delete("/budgets/export-budget", headers=auth).status_code == 200
    assert client.delete("/transactions/export-tx", headers=auth).status_code == 200
    assert client.delete("/accounts/export-account", headers=auth).status_code == 200

    response = client.get("/backup/export", headers=auth)
    assert response.status_code == 200, response.text
    body = response.json()
    assert (body["kind"], body["schema_version"]) == ("suixiangji.backup", 2)
    assert body["profile"]["display_name"] == "Original profile"
    assert body["accounts"][0]["opening_balance"] == "10.125678"
    assert body["budgets"][0]["limit"] == "20.125678"
    assert body["transactions"][0]["amount"] == "2.125678"
    categories = {item["id"]: item for item in body["categories"]}
    accounts = {item["id"]: item for item in body["accounts"]}
    budgets = {item["id"]: item for item in body["budgets"]}
    transactions = {item["id"]: item for item in body["transactions"]}
    assert categories["export-category"]["active"] is False
    assert accounts["export-account"]["deleted_at"] is not None
    assert budgets["export-budget"]["deleted_at"] is not None
    assert transactions["export-tx"]["deleted_at"] is not None
    assert all("server_version" not in item and "updated_at" not in item for key in ("accounts", "categories", "transactions", "budgets") for item in body[key])
    assert "password_hash" not in response.text
    assert "recovery_code" not in response.text
    assert "access_token" not in response.text


def test_v2_export_can_be_imported_back_without_losing_snapshots(api):
    client, _, auth = _user(api, "roundtrip-user")
    assert client.post("/accounts", headers=auth, json={"id": "roundtrip-account", "name": "Roundtrip", "opening_balance": "8.125678"}).status_code == 200
    assert client.post("/categories", headers=auth, json={"id": "roundtrip-category", "name": "Roundtrip category"}).status_code == 200
    assert client.post("/budgets", headers=auth, json={"id": "roundtrip-budget", "category_id": "roundtrip-category", "month": "2026-09", "limit": "9.125678"}).status_code == 200
    assert client.post("/transactions", headers=auth, json={"id": "roundtrip-tx", "client_op_id": "roundtrip-op", "kind": "expense", "amount": "1.125678", "account_id": "roundtrip-account", "category_id": "roundtrip-category", "occurred_on": "2026-09-01"}).status_code == 200
    exported = client.get("/backup/export", headers=auth).json()
    exported["restore_id"] = "roundtrip-restore"
    restored = client.post("/backup/restore", headers=auth, json=exported)
    assert restored.status_code == 200, restored.text
    assert restored.json()["accounts"] == 1
    assert restored.json()["categories"] == len(exported["categories"])
    assert restored.json()["budgets"] == 1
    assert restored.json()["transactions"] == 1
    current = client.get("/backup/export", headers=auth).json()
    account = next(item for item in current["accounts"] if item["id"] == "roundtrip-account")
    transaction = next(item for item in current["transactions"] if item["id"] == "roundtrip-tx")
    assert account["opening_balance"] == "8.125678"
    assert transaction["client_op_id"] == "roundtrip-op"


def test_restore_merges_new_overlapping_and_unmentioned_records_and_invalidates_reports(api):
    client, sessions, auth = _user(api, "merge-user")
    assert client.post("/accounts", headers=auth, json={"id": "keep-account", "name": "Keep"}).status_code == 200
    assert client.post("/accounts", headers=auth, json={"id": "overlap-account", "name": "Before"}).status_code == 200
    assert client.post("/categories", headers=auth, json={"id": "keep-category", "name": "Keep category"}).status_code == 200
    assert client.get("/reports/monthly/2026-09", headers=auth).status_code == 200
    with sessions() as db:
        from app.models import MonthlyReport, NetWorthSnapshot, User
        uid = client.get("/auth/me", headers=auth).json()["id"]
        assert db.scalar(select(MonthlyReport).where(MonthlyReport.user_id == uid)) is not None
        assert db.scalar(select(NetWorthSnapshot).where(NetWorthSnapshot.user_id == uid)) is not None

    payload = _restore_payload(owner_id=client.get("/auth/me", headers=auth).json()["id"], restore_id="merge-restore")
    payload["accounts"].append({"id": "overlap-account", "name": "After", "kind": "asset", "currency": "CNY", "opening_balance": "5", "deleted_at": None})
    response = client.post("/backup/restore", headers=auth, json=payload)
    assert response.status_code == 200, response.text
    assert response.json()["replayed"] is False
    accounts = {item["id"]: item for item in client.get("/accounts", headers=auth).json()["items"]}
    assert accounts["keep-account"]["name"] == "Keep"
    assert accounts["overlap-account"]["name"] == "After"
    with sessions() as db:
        from app.models import MonthlyReport, NetWorthSnapshot, User
        uid = client.get("/auth/me", headers=auth).json()["id"]
        user = db.get(User, uid)
        assert user.display_name == "Restored profile"
        assert user.quick_memories == [{"text": "保存发票"}]
        assert db.scalar(select(MonthlyReport).where(MonthlyReport.user_id == uid)) is None
        assert db.scalar(select(NetWorthSnapshot).where(NetWorthSnapshot.user_id == uid)) is None


def test_restore_reallocates_versions_and_pull_includes_all_entities_and_tombstones(api):
    client, sessions, auth = _user(api, "version-user")
    uid = client.get("/auth/me", headers=auth).json()["id"]
    with sessions() as db:
        from app.models import User
        initial_version = db.get(User, uid).sync_version
    response = client.post("/backup/restore", headers=auth, json=_restore_payload(owner_id=uid, restore_id="version-restore"))
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["server_version"] == initial_version + 4
    assert result["accounts"] == result["categories"] == result["transactions"] == result["budgets"] == 1
    with sessions() as db:
        from app.models import Account, Budget, Category, Transaction, User
        user = db.get(User, uid)
        versions = [
            db.get(Account, "restore-account").server_version,
            db.get(Category, "restore-category").server_version,
            db.get(Budget, "restore-budget").server_version,
            db.get(Transaction, "restore-transaction").server_version,
        ]
        assert user.sync_version == initial_version + 4
        assert versions == list(range(initial_version + 1, initial_version + 5))
        assert all(db.get(model, identifier).server_version != old for model, identifier, old in ((Account, "restore-account", 999), (Category, "restore-category", 998), (Budget, "restore-budget", 997), (Transaction, "restore-transaction", 996)))
    pulled = client.get(f"/sync/pull?since_version={initial_version}", headers=auth)
    assert pulled.status_code == 200, pulled.text
    body = pulled.json()
    assert [item["id"] for item in body["accounts"]] == ["restore-account"]
    assert [item["id"] for item in body["categories"]] == ["restore-category"]
    assert [item["id"] for item in body["budgets"]] == ["restore-budget"]
    assert [item["id"] for item in body["transactions"]] == ["restore-transaction"]


def test_restore_idempotency_and_conflicting_reuse_are_atomic(api):
    client, sessions, auth = _user(api, "idempotent-user")
    payload = _restore_payload(owner_id=client.get("/auth/me", headers=auth).json()["id"], restore_id="same-restore")
    first = client.post("/backup/restore", headers=auth, json=payload)
    assert first.status_code == 200, first.text
    with sessions() as db:
        from app.models import SyncOperation, User
        uid = client.get("/auth/me", headers=auth).json()["id"]
        before_version = db.get(User, uid).sync_version
        before_receipts = db.scalars(select(SyncOperation).where(SyncOperation.user_id == uid)).all()
    replay = client.post("/backup/restore", headers=auth, json=payload)
    assert replay.status_code == 200, replay.text
    assert replay.json()["replayed"] is True
    with sessions() as db:
        from app.models import SyncOperation, User
        uid = client.get("/auth/me", headers=auth).json()["id"]
        assert db.get(User, uid).sync_version == before_version
        assert len(db.scalars(select(SyncOperation).where(SyncOperation.user_id == uid)).all()) == len(before_receipts)

    conflict = _restore_payload(owner_id=client.get("/auth/me", headers=auth).json()["id"], restore_id="same-restore")
    conflict["profile"]["display_name"] = "Different"
    response = client.post("/backup/restore", headers=auth, json=conflict)
    assert response.status_code == 409, response.text
    assert client.get("/auth/me", headers=auth).json()["display_name"] == "Restored profile"


def test_v1_restore_compatibility_and_backup_authentication(api):
    client, _, auth = _user(api, "v1-user")
    assert client.get("/backup/export").status_code == 401
    assert client.post("/backup/restore", json={"accounts": []}).status_code == 401
    v1 = {
        "accounts": [{"id": "v1-account", "name": "V1", "kind": "asset", "currency": "CNY", "opening_balance": 1}],
        "transactions": [{"id": "v1-tx", "client_op_id": "v1-op", "kind": "expense", "amount": 1, "currency": "CNY", "account_id": "v1-account", "occurred_on": "2026-09-01"}],
    }
    response = client.post("/backup/restore", headers=auth, json=v1)
    assert response.status_code == 200, response.text
    assert response.json()["accounts"] == 1
    assert client.get("/transactions", headers=auth).json()["items"][0]["id"] == "v1-tx"


def test_restore_rejects_foreign_owner_and_unknown_sections_without_writes(api):
    client, sessions, auth = _user(api, "validation-user")
    uid = client.get("/auth/me", headers=auth).json()["id"]
    foreign = _restore_payload(owner_id="some-other-user", restore_id="foreign-owner")
    assert client.post("/backup/restore", headers=auth, json=foreign).status_code == 422
    unknown = _restore_payload(owner_id=uid, restore_id="unknown-section")
    unknown["unexpected"] = []
    assert client.post("/backup/restore", headers=auth, json=unknown).status_code == 422
    with sessions() as db:
        from app.models import Account, User
        assert db.get(User, uid).sync_version == len(DEFAULT_CATEGORIES)
        assert db.scalar(select(Account).where(Account.id == "restore-account")) is None


def test_profile_only_restore_has_a_replayable_receipt_without_advancing_sync(api):
    client, sessions, auth = _user(api, "profile-only-user")
    uid = client.get("/auth/me", headers=auth).json()["id"]
    payload = {
        "kind": "suixiangji.backup",
        "schema_version": 2,
        "owner_id": uid,
        "profile": {"display_name": "Profile only", "quick_memories": []},
        "accounts": [],
        "categories": [],
        "transactions": [],
        "budgets": [],
        "restore_id": "profile-only",
    }
    first = client.post("/backup/restore", headers=auth, json=payload)
    assert first.status_code == 200, first.text
    assert first.json()["server_version"] == len(DEFAULT_CATEGORIES)
    assert client.get("/auth/me", headers=auth).json()["display_name"] == "Profile only"
    replay = client.post("/backup/restore", headers=auth, json=payload)
    assert replay.status_code == 200 and replay.json()["replayed"] is True
    with sessions() as db:
        from app.models import SyncOperation, User
        assert db.get(User, uid).sync_version == len(DEFAULT_CATEGORIES)
        assert len(db.scalars(select(SyncOperation).where(SyncOperation.user_id == uid)).all()) == 1


@pytest.mark.parametrize("route", ["/backup/export", "/backup/restore"])
def test_backup_routes_require_bearer_auth(api, route):
    client, _, _ = _user(api, "auth-user-" + route.rsplit("/", 1)[-1])
    response = client.get(route) if route.endswith("export") else client.post(route, json={"accounts": []})
    assert response.status_code == 401
