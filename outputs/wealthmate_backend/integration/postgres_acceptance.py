"""Real HTTP + PostgreSQL acceptance. Creates synthetic users/schema; no drops.

Run inside the isolated integration Compose API container. Never point this
script at a live-user service: account deletion only targets generated users.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
import os
from pathlib import Path
import secrets
import subprocess
import sys
from threading import Barrier
from uuid import uuid4

import httpx
from sqlalchemy import create_engine, select, text
from sqlalchemy.engine import make_url

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import get_settings
from app.db import SessionLocal
from app.models import Account, AgentLog, Budget, Category, ExchangeRate, InviteCode, MonthlyReport, NetWorthSnapshot, SyncOperation, Transaction, User
from app.security import hash_password


def check(response, expected):
    # Do not include successful registration bodies (they contain live JWTs).
    assert response.status_code == expected, f"{response.request.method} {response.request.url.path}: {response.status_code}, expected {expected}"
    return response.json()


def new_invite(max_uses):
    code = secrets.token_urlsafe(32)
    with SessionLocal.begin() as db:
        db.add(InviteCode(code=code, max_uses=max_uses, expires_at=datetime.now(timezone.utc) + timedelta(hours=1)))
    return code


def concurrent(requests):
    barrier = Barrier(len(requests))
    def run(callback):
        barrier.wait(timeout=10)
        return callback()
    with ThreadPoolExecutor(max_workers=len(requests)) as pool:
        return list(pool.map(run, requests))


def legacy_migration():
    """An additional retained PostgreSQL schema, never touches public tables."""
    settings = get_settings()
    schema = "beta_legacy_" + uuid4().hex[:12]
    root = create_engine(settings.database_url)
    with root.begin() as db:
        db.execute(text(f'CREATE SCHEMA "{schema}"'))  # generated hex identifier only
    url = make_url(settings.database_url).update_query_dict({"options": f"-csearch_path={schema}"})
    engine = create_engine(url)
    from migrations.legacy_schema import Base as LegacyBase
    with engine.begin() as db:
        db.execute(text("CREATE TABLE users (id VARCHAR(64) PRIMARY KEY, username VARCHAR(128) NOT NULL UNIQUE, password_hash VARCHAR(256) NOT NULL, sync_version INTEGER NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"))
        db.execute(text("INSERT INTO users (id,username,password_hash,sync_version) VALUES ('legacy','Legacy-User',:hash,42)"), {"hash": hash_password("test-only-legacy-password")})
        LegacyBase.metadata.create_all(db, checkfirst=True)
        db.execute(text("INSERT INTO accounts (id,user_id,name,kind,account_kind,currency,opening_balance,is_liquid,is_default_payment,server_version) VALUES ('legacy-account','legacy','legacy account','asset','other','CNY',123,false,false,40)"))
        db.execute(text("INSERT INTO transactions (id,user_id,client_op_id,kind,amount,currency,cny_amount,conversion_status,account_id,occurred_on,server_version) VALUES ('legacy-tx','legacy','legacy-op','expense',12,'CNY',12,'ready','legacy-account','2026-09-01',42)"))
    env = {**os.environ, "WEALTHMATE_DATABASE_URL": url.render_as_string(hide_password=False)}
    result = subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, "Legacy PostgreSQL migration failed (details withheld to protect connection credentials)"
    # Execute real API handlers against the migrated PostgreSQL schema in an
    # isolated process; main acceptance below separately uses live HTTP server.
    script = '''
from fastapi.testclient import TestClient
from app.main import app
with TestClient(app) as client:
    response = client.post('/auth/login', json={'username':'LEGACY-USER','password':'test-only-legacy-password'})
    assert response.status_code == 200
    headers = {'Authorization':'Bearer '+response.json()['access_token']}
    pull = client.get('/sync/pull',headers=headers).json()
    assert pull['server_version'] == 42
    assert pull['accounts'][0]['server_version'] == 40
    assert pull['accounts'][0]['opening_balance'] == 123
    assert pull['transactions'][0]['server_version'] == 42
    assert pull['transactions'][0]['client_op_id'] == 'legacy-op'
    assert pull['transactions'][0]['amount'] == 12
'''
    result = subprocess.run([sys.executable, "-c", script], env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, "Migrated legacy login/financial/version verification failed"
    engine.dispose()
    root.dispose()
    print("PASS legacy PostgreSQL upgrade, login, finances and versions (synthetic schema retained)")


def main():
    if os.environ.get("WEALTHMATE_ALLOW_SYNTHETIC_INTEGRATION") != "1":
        raise RuntimeError("Set WEALTHMATE_ALLOW_SYNTHETIC_INTEGRATION=1 only in an isolated Compose project")
    assert make_url(get_settings().database_url).get_backend_name() == "postgresql", "Real PostgreSQL is mandatory"
    prefix = "beta_test_" + uuid4().hex[:8]
    password = secrets.token_urlsafe(24)
    with httpx.Client(base_url="http://127.0.0.1:8000", timeout=30) as client:
        shared = new_invite(2)
        def registration(name, code):
            return client.post("/auth/register", json={"username": name, "password": password, "invite_code": code})
        a = check(registration(prefix + "_a", shared), 201)
        b = check(registration(prefix + "_b", shared), 201)
        ah = {"Authorization": "Bearer " + a["access_token"]}
        bh = {"Authorization": "Bearer " + b["access_token"]}
        logged = check(client.post("/auth/login", json={"username": (prefix + "_a").upper(), "password": password}), 200)
        assert logged["user_id"] == a["user_id"]
        account = check(client.post("/accounts", headers=ah, json={"name": prefix, "opening_balance": 100}), 200)
        category = check(client.post("/categories", headers=ah, json={"name": prefix}), 200)
        tx = check(client.post("/transactions", headers=ah, json={"client_op_id": prefix + "_tx", "kind": "expense", "amount": 12, "account_id": account["id"], "category_id": category["id"], "occurred_on": "2026-09-08"}), 200)
        check(client.post("/budgets", headers=ah, json={"month": "2026-09", "category_id": category["id"], "limit": 100}), 200)
        operation = {"client_op_id": prefix + "_sync", "entity": "accounts", "entity_id": prefix + "_offline", "type": "upsert", "payload": {"name": "offline " + prefix}}
        pushed = check(client.post("/sync/push", headers=ah, json={"operations": [operation]}), 200)
        replay = check(client.post("/sync/push", headers=ah, json={"operations": [operation]}), 200)
        assert pushed["server_version"] == replay["server_version"]
        assert replay["accepted"][0]["created"] is False
        pull = check(client.get("/sync/pull", headers=ah), 200)
        assert any(row["id"] == tx["id"] for row in pull["transactions"])
        # Logout is client-side credential removal; B sends only B's token.
        for route in ("/accounts", "/transactions", "/budgets", "/backup/export", "/sync/pull", "/wealth", "/reports/monthly/2026-09"):
            response = client.get(route, headers=bh)
            check(response, 200)
            assert account["id"] not in response.text and tx["id"] not in response.text
        check(client.patch(f"/accounts/{account['id']}", headers=bh, json={"name": "attack"}), 404)
        check(client.delete(f"/transactions/{tx['id']}", headers=bh), 404)
        check(client.post("/sync/push", headers=bh, json={"operations": [operation]}), 404)
        check(client.post("/backup/restore", headers=bh, json={"accounts": [account]}), 404)
        check(client.request("DELETE", "/auth/me", headers=ah, json={"current_password": "bad"}), 403)
        check(client.get("/auth/me", headers=ah), 200)
        check(client.request("DELETE", "/auth/me", headers=ah, json={"current_password": password}), 200)
        check(client.get("/auth/me", headers=ah), 401)
        check(client.get("/auth/me", headers=bh), 200)
        with SessionLocal() as db:
            assert db.get(User, a["user_id"]) is None
            for model in (Account, Category, Transaction, Budget, SyncOperation, NetWorthSnapshot, MonthlyReport, AgentLog):
                assert not db.scalars(select(model).where(model.user_id == a["user_id"])).all()
        print("PASS live FastAPI/PostgreSQL registration, login, CRUD, sync replay, A/B isolation, deletion")
        rotations = concurrent([
            lambda: client.post("/auth/password", headers=bh, json={"current_password": password, "new_password": secrets.token_urlsafe(24)}),
            lambda: client.post("/auth/password", headers=bh, json={"current_password": password, "new_password": secrets.token_urlsafe(24)}),
        ])
        assert sorted(r.status_code for r in rotations) == [200, 401]
        check(client.get("/auth/me", headers=bh), 401)
        winner = next(r for r in rotations if r.status_code == 200).json()
        check(client.get("/auth/me", headers={"Authorization": "Bearer " + winner["access_token"]}), 200)
        print("PASS PostgreSQL concurrent password rotation revokes stale authorization")
        once = new_invite(1)
        results = concurrent([lambda: registration(prefix + "_c", once), lambda: registration(prefix + "_d", once)])
        assert sorted(r.status_code for r in results) == [201, 400]
        codes = [new_invite(1), new_invite(1)]
        results = concurrent([lambda: registration(prefix + "_same", codes[0]), lambda: registration(prefix + "_same", codes[1])])
        assert sorted(r.status_code for r in results) == [201, 409]
        with SessionLocal() as db:
            assert db.get(InviteCode, once).used_count == 1
            assert sorted(db.get(InviteCode, code).used_count for code in codes) == [0, 1]
        print("PASS PostgreSQL concurrent invite capacity and duplicate-username rollback")
    legacy_migration()
    print("PASS PostgreSQL acceptance complete; synthetic records/volumes retained")


if __name__ == "__main__":
    main()

