"""Two real DB users; exercise every tenant-facing API boundary."""
import pytest
from sqlalchemy import select

from test_user_system import api, headers, invite, register


@pytest.fixture
def tenants(api):
    client, sessions = api
    invite(sessions)
    a, b = headers(register(client, "user-a")), headers(register(client, "user-b"))
    resources = {
        "accounts": {"id": "b-account", "name": "B-PRIVATE", "opening_balance": 9876},
        "categories": {"id": "b-category", "name": "B-PRIVATE", "kind": "expense"},
        "transactions": {"id": "b-transaction", "client_op_id": "b-op", "account_id": "b-account", "category_id": "b-category", "kind": "expense", "amount": 765, "occurred_on": "2026-09-01", "note": "B-PRIVATE"},
        "budgets": {"id": "b-budget", "category_id": "b-category", "month": "2026-09", "limit": 1234},
    }
    for entity, body in resources.items():
        response = client.post("/" + entity, headers=b, json=body)
        assert response.status_code == 200, response.text
    yield client, sessions, a, b, resources


@pytest.mark.parametrize("entity", ["accounts", "categories", "transactions", "budgets"])
def test_foreign_resource_read_create_patch_delete_rejected(tenants, entity):
    client, _, a, b, resources = tenants
    body = resources[entity]
    identifier = body["id"]
    assert identifier not in client.get("/" + entity, headers=a).text
    # Individual GET is not an existing route; existing and absent IDs both
    # return method-not-allowed, without revealing resource existence.
    assert client.get(f"/{entity}/{identifier}", headers=a).status_code == 405
    assert client.get(f"/{entity}/absent", headers=a).status_code == 405
    assert client.post("/" + entity, headers=a, json=body).status_code == 404
    patch = body if entity in ("accounts", "transactions") else {"name": "tampered"} if entity == "categories" else {"limit": 1}
    assert client.patch(f"/{entity}/{identifier}", headers=a, json=patch).status_code == 404
    if entity == "categories":
        response = client.post(f"/categories/{identifier}/archive", headers=a)
    else:
        response = client.delete(f"/{entity}/{identifier}", headers=a)
    assert response.status_code == 404
    assert "B-PRIVATE" in client.get("/accounts", headers=b).text


@pytest.mark.parametrize("entity", ["accounts", "categories", "transactions", "budgets"])
@pytest.mark.parametrize("operation", ["upsert", "delete"])
def test_sync_cannot_mutate_other_user_and_rolls_back_whole_batch(tenants, entity, operation):
    from app.models import SyncOperation, User
    client, sessions, a, b, resources = tenants
    before = client.get("/sync/pull", headers=b).json()
    response = client.post("/sync/push", headers=a, json={"operations": [
        {"client_op_id": "a-preceding", "entity": "accounts", "entity_id": "a-rollback", "type": "upsert", "payload": {"name": "rollback"}},
        {"client_op_id": "a-attack", "entity": entity, "entity_id": resources[entity]["id"], "type": operation, "payload": resources[entity]},
    ]})
    assert response.status_code == 404, response.text
    assert client.get("/sync/pull", headers=b).json() == before
    assert client.get("/accounts", headers=a).json()["items"] == []
    assert client.get("/sync/pull", headers=a).json()["server_version"] == 5
    with sessions() as db:
        assert db.scalar(select(SyncOperation).where(SyncOperation.client_op_id == "a-preceding")) is None


@pytest.mark.parametrize("field,foreign_id", [("account_id", "b-account"), ("from_account_id", "b-account"), ("to_account_id", "b-account"), ("category_id", "b-category")])
def test_foreign_transaction_references_rejected_like_missing_resources(tenants, field, foreign_id):
    client, _, a, _, _ = tenants
    assert client.post("/accounts", headers=a, json={"id": "a-account", "name": "own"}).status_code == 200
    body = {"client_op_id": "a-reference", "kind": "expense", "amount": 1, "account_id": "a-account", "occurred_on": "2026-09-01", field: foreign_id}
    denied = client.post("/transactions", headers=a, json=body)
    absent = client.post("/transactions", headers=a, json={**body, field: "missing"})
    assert denied.status_code == absent.status_code == 422
    assert client.get("/transactions", headers=a).json()["items"] == []


def test_foreign_budget_category_rejected(tenants):
    client, _, a, _, _ = tenants
    response = client.post("/budgets", headers=a, json={"category_id": "b-category", "month": "2026-09", "limit": 1})
    assert response.status_code == 422


def test_backup_restore_is_tenant_scoped_and_atomic(tenants):
    client, _, a, b, resources = tenants
    own = client.get("/backup/export", headers=a).json()
    assert own["accounts"] == own["transactions"] == []
    response = client.post("/backup/restore", headers=a, json={"accounts": [{"id": "a-rollback", "name": "rollback"}, resources["accounts"]]})
    assert response.status_code == 404
    assert client.get("/accounts", headers=a).json()["items"] == []
    response = client.post("/backup/restore", headers=a, json={"transactions": [resources["transactions"]]})
    assert response.status_code == 404
    assert client.get("/backup/export", headers=b).json()["transactions"][0]["note"] == "B-PRIVATE"


def test_stats_wealth_reports_agent_and_sync_read_only_own_data(tenants):
    from app.models import AgentLog, MonthlyReport, NetWorthSnapshot
    client, sessions, a, b, _ = tenants
    b_report = client.get("/reports/monthly/2026-09", headers=b)
    assert b_report.status_code == 200
    for route in ("/stats?month=2026-09", "/wealth", "/reports/monthly/2026-09", "/sync/pull"):
        response = client.get(route, headers=a)
        assert response.status_code == 200, response.text
        assert "B-PRIVATE" not in response.text
        assert "b-account" not in response.text
    assert client.get("/stats?month=2026-09", headers=a).json()["expense"] == 0
    assert client.get("/wealth", headers=a).json()["net_worth"] == 0
    draft = client.post("/agent/draft", headers=a, json={"text": "B-PRIVATE 支付 20 元"})
    assert draft.status_code == 200
    assert "b-account" not in draft.text and "b-category" not in draft.text
    aid = client.get("/auth/me", headers=a).json()["id"]
    bid = client.get("/auth/me", headers=b).json()["id"]
    with sessions() as db:
        assert db.scalar(select(AgentLog).where(AgentLog.user_id == aid)) is not None
        for model in (MonthlyReport, NetWorthSnapshot):
            assert db.scalar(select(model).where(model.user_id == aid)) is not None
            assert db.scalar(select(model).where(model.user_id == bid)) is not None

