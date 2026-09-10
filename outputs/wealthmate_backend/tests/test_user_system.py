"""Behavioral account/tenant contracts, with real SQLAlchemy transactions."""
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def api(tmp_path, monkeypatch):
    from app.config import get_settings
    monkeypatch.setenv("WEALTHMATE_DEMO_ENABLED", "false")
    monkeypatch.setenv("WEALTHMATE_JWT_SECRET", "test-only-user-system-signing-key-00000000")
    get_settings.cache_clear()
    from app.db import Base, get_db
    from app.main import app
    from app.core.rate_limit import auth_limiter
    auth_limiter.clear()
    engine = create_engine(f"sqlite:///{tmp_path / 'users.db'}", connect_args={"check_same_thread": False})
    event.listen(engine, "connect", lambda connection, _: connection.execute("PRAGMA foreign_keys=ON"))
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine, expire_on_commit=False)
    def database():
        with sessions() as session:
            yield session
    app.dependency_overrides[get_db] = database
    client = TestClient(app)
    yield client, sessions
    client.close()
    app.dependency_overrides.clear()
    engine.dispose()
    get_settings.cache_clear()


def invite(sessions, code="test-only-invite", **kwargs):
    from app.models import InviteCode
    with sessions.begin() as db:
        db.add(InviteCode(code=code, max_uses=kwargs.pop("max_uses", 10), **kwargs))
    return code


def register(client, username="alice", code="test-only-invite", **kwargs):
    return client.post("/auth/register", json={"username": username, "password": "test-password", "invite_code": code, **kwargs})


def headers(response):
    assert response.status_code in (200, 201), response.text
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def test_registration_requires_server_invite(api):
    client, _ = api
    response = register(client, code="invalid")
    assert response.status_code == 400
    assert "邀请码" in response.json()["detail"]


def test_demo_is_disabled_by_default(api):
    client, _ = api
    from app.config import get_settings
    settings = get_settings()
    result = client.post("/auth/login", json={"username": settings.demo_username, "password": settings.demo_password})
    assert result.status_code == 401


def test_register_normalized_login_hash_profile_and_seed_versions(api):
    from app.models import User, Category, InviteCode
    from app.security import verify_password
    client, sessions = api
    invite(sessions)
    response = register(client, " Alice ", display_name=" Alice's ledger ")
    assert response.status_code == 201, response.text
    profile = client.get("/auth/me", headers=headers(response)).json()
    assert profile["username"] == "alice"
    assert profile["display_name"] == "Alice's ledger"
    with sessions() as db:
        user = db.get(User, profile["id"])
        assert user.password_hash != "test-password"
        assert verify_password("test-password", user.password_hash)
        assert user.sync_version == 5
        rows = db.scalars(select(Category).where(Category.user_id == user.id)).all()
        assert sorted(row.server_version for row in rows) == [1, 2, 3, 4, 5]
        assert db.scalar(select(InviteCode)).used_count == 1
    for name in ("alice", "ALICE", " Alice "):
        assert client.post("/auth/login", json={"username": name, "password": "test-password"}).status_code == 200
    assert client.get("/sync/pull?since_version=0", headers=headers(response)).json()["server_version"] == 5
    assert "password" not in response.text


@pytest.mark.parametrize("username", ["ab", "x" * 33, "a b", "中文名", "a@b", "   ", "Kelly"])
def test_registration_username_rules(api, username):
    assert register(api[0], username).status_code == 422


@pytest.mark.parametrize("password", ["short", "", "x" * 257])
def test_registration_password_rules(api, password):
    assert register(api[0], password=password).status_code == 422


@pytest.mark.parametrize("options", [{"enabled": False}, {"max_uses": 1, "used_count": 1}, {"expires_at": datetime.now(timezone.utc) - timedelta(days=1)}])
def test_invalid_invite_never_creates_partial_user(api, options):
    from app.models import User, Category
    client, sessions = api
    invite(sessions, **options)
    assert register(client).status_code == 400
    with sessions() as db:
        assert db.scalar(select(User)) is None
        assert db.scalar(select(Category)) is None


def test_duplicate_registration_rolls_back_invite_consumption(api):
    from app.models import InviteCode, User
    client, sessions = api
    invite(sessions)
    assert register(client).status_code == 201
    assert register(client, "ALICE").status_code == 409
    with sessions() as db:
        assert db.scalar(select(InviteCode)).used_count == 1
        assert len(db.scalars(select(User)).all()) == 1


def test_username_unique_constraint_is_case_insensitive(api):
    from app.models import User
    from app.security import hash_password
    from sqlalchemy.exc import IntegrityError
    _, sessions = api
    with sessions.begin() as db:
        db.add(User(id="legacy", username="MixedCase", password_hash=hash_password("test-password")))
    with pytest.raises(IntegrityError):
        with sessions.begin() as db:
            db.add(User(id="duplicate", username="mixedcase", password_hash="not-real"))


def test_rename_password_rotation_and_uniform_login_failure(api):
    client, sessions = api
    invite(sessions)
    old = headers(register(client))
    headers(register(client, "bob"))
    assert client.patch("/auth/me", headers=old, json={"username": " BOB "}).status_code == 409
    renamed = client.patch("/auth/me", headers=old, json={"username": " ALICE-2 ", "display_name": "昵称", "quick_memories": [{"text": "记账"}]})
    current = headers(renamed)
    assert renamed.json()["username"] == "alice-2"
    assert renamed.json()["quick_memories"] == [{"text": "记账"}]
    assert client.get("/auth/me", headers=old).status_code == 401
    rotated = client.post("/auth/password", headers=current, json={"current_password": "test-password", "new_password": "new-password"})
    assert client.get("/auth/me", headers=headers(rotated)).status_code == 200
    assert client.get("/auth/me", headers=current).status_code == 401
    failure = client.post("/auth/login", json={"username": "alice-2", "password": "bad"})
    absent = client.post("/auth/login", json={"username": "absent", "password": "bad"})
    assert failure.status_code == absent.status_code == 401
    assert failure.json() == absent.json()
    assert client.post("/auth/login", json={"username": "ALICE-2", "password": "new-password"}).status_code == 200


@pytest.mark.parametrize("override", [{"auth_version": None}, {"auth_version": "bad"}, {"auth_version": True}, {"exp": None}, {"sub": None}])
def test_invalid_required_jwt_claims_rejected(api, override):
    from jose import jwt
    from app.config import get_settings
    from app.models import User
    client, sessions = api
    with sessions.begin() as db:
        db.add(User(id="jwt-user", username="jwt-user", password_hash="test-only"))
    claims = {"sub": "jwt-user", "auth_version": 0, "exp": datetime.now(timezone.utc) + timedelta(hours=1)}
    claims.update(override)
    claims = {key: value for key, value in claims.items() if value is not None}
    token = jwt.encode(claims, get_settings().jwt_secret, algorithm="HS256")
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {token}"}).status_code == 401


def test_deletion_is_atomic_scoped_and_rejects_wrong_password(api):
    from app.models import User, Account, Category, Transaction, Budget, SyncOperation, NetWorthSnapshot, MonthlyReport, AgentLog, ExchangeRate
    client, sessions = api
    invite(sessions)
    alice = register(client)
    bob = register(client, "bob")
    a, b = headers(alice), headers(bob)
    uid = alice.json()["user_id"]
    account = client.post("/accounts", headers=a, json={"id": "delete-account", "name": "delete account"})
    assert account.status_code == 200
    category = client.get("/categories", headers=a).json()["items"][0]["id"]
    assert client.post("/transactions", headers=a, json={"client_op_id": "delete-tx", "amount": 12, "kind": "expense", "account_id": "delete-account", "category_id": category, "occurred_on": "2026-09-01"}).status_code == 200
    assert client.post("/budgets", headers=a, json={"id": "delete-budget", "category_id": category, "month": "2026-09", "limit": 10}).status_code == 200
    with sessions.begin() as db:
        db.add(SyncOperation(user_id=uid, client_op_id="test-op", entity="accounts", entity_id="delete-account", server_version=9))
        db.add(NetWorthSnapshot(user_id=uid, month="2026-09"))
        db.add(MonthlyReport(user_id=uid, month="2026-09", metrics={}, narrative="test"))
        db.add(AgentLog(user_id=uid, task="test", status="success"))
        db.add(ExchangeRate(base_currency="USD", quote_currency="CNY", rate=7, rate_date=date(2026, 9, 1), source="test-only"))
    assert client.request("DELETE", "/auth/me", headers=a, json={"current_password": "bad"}).status_code == 403
    assert client.get("/accounts", headers=a).json()["items"]
    result = client.request("DELETE", "/auth/me", headers=a, json={"current_password": "test-password"})
    assert result.status_code == 200, result.text
    assert client.get("/auth/me", headers=a).status_code == 401
    assert client.get("/auth/me", headers=b).status_code == 200
    with sessions() as db:
        for model in (Account, Category, Transaction, Budget, SyncOperation, NetWorthSnapshot, MonthlyReport, AgentLog):
            assert not db.scalars(select(model).where(model.user_id == uid)).all(), model.__name__
        assert db.get(User, uid) is None
        assert db.get(User, bob.json()["user_id"]) is not None
        assert db.scalar(select(ExchangeRate)) is not None


def test_deletion_rollback_preserves_all_rows_on_database_failure(api):
    from app.models import User, Account
    client, sessions = api
    invite(sessions)
    registered = register(client)
    auth = headers(registered)
    assert client.post("/accounts", headers=auth, json={"id": "rollback-account", "name": "retain"}).status_code == 200
    engine = sessions.kw["bind"]
    def reject_user_delete(connection, cursor, statement, parameters, context, many):
        if statement.upper().startswith("DELETE FROM USERS"):
            raise RuntimeError("test-only injected database failure")
    event.listen(engine, "before_cursor_execute", reject_user_delete)
    try:
        with pytest.raises(RuntimeError, match="test-only injected"):
            client.request("DELETE", "/auth/me", headers=auth, json={"current_password": "test-password"})
    finally:
        event.remove(engine, "before_cursor_execute", reject_user_delete)
    with sessions() as db:
        assert db.get(User, registered.json()["user_id"]) is not None
        assert db.get(Account, "rollback-account") is not None


def test_ordinary_user_cannot_write_public_exchange_rates(api):
    from app.models import ExchangeRate
    client, sessions = api
    invite(sessions)
    auth = headers(register(client))
    response = client.post("/exchange/rates", headers=auth, json={"base_currency": "USD", "quote_currency": "CNY", "rate": 999, "rate_date": "2026-09-08", "source": "attacker"})
    assert response.status_code == 403
    with sessions() as db:
        assert db.scalar(select(ExchangeRate)) is None


def test_beta_websocket_is_disabled(api):
    from starlette.websockets import WebSocketDisconnect
    with pytest.raises(WebSocketDisconnect):
        with api[0].websocket_connect("/ws/sync"):
            pytest.fail("Beta must not accept this noncore unauthenticated entry")


def test_concurrent_invite_consumption_cannot_exceed_capacity(api):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from app.models import InviteCode, User
    client, sessions = api
    invite(sessions, max_uses=1)
    barrier = Barrier(2)
    def attempt(name):
        barrier.wait(timeout=5)
        return register(client, name).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(attempt, ["concurrent-a", "concurrent-b"]))
    assert sorted(results) == [201, 400]
    with sessions() as db:
        assert db.scalar(select(InviteCode)).used_count == 1
        assert len(db.scalars(select(User)).all()) == 1


def test_concurrent_duplicate_registration_rolls_back_losing_invite(api):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from app.models import InviteCode, User
    client, sessions = api
    codes = [invite(sessions, "test-only-code-a"), invite(sessions, "test-only-code-b")]
    barrier = Barrier(2)
    def attempt(code):
        barrier.wait(timeout=5)
        return register(client, "same-user", code=code).status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(attempt, codes))
    assert sorted(results) == [201, 409]
    with sessions() as db:
        assert sorted(row.used_count for row in db.scalars(select(InviteCode))) == [0, 1]
        assert len(db.scalars(select(User)).all()) == 1


def test_seed_failure_rolls_back_user_categories_and_invite(api):
    from app.models import InviteCode, User, Category
    client, sessions = api
    invite(sessions)
    engine = sessions.kw["bind"]
    def fail_category_insert(connection, cursor, statement, parameters, context, many):
        if statement.upper().startswith("INSERT INTO CATEGORIES"):
            raise RuntimeError("test-only seed failure")
    event.listen(engine, "before_cursor_execute", fail_category_insert)
    try:
        with pytest.raises(RuntimeError, match="test-only seed failure"):
            register(client)
    finally:
        event.remove(engine, "before_cursor_execute", fail_category_insert)
    with sessions() as db:
        assert db.scalar(select(User)) is None
        assert db.scalar(select(Category)) is None
        assert db.scalar(select(InviteCode)).used_count == 0


@pytest.mark.parametrize("late_action", ["password", "rename", "delete"])
def test_stale_auth_request_cannot_overwrite_completed_password_change(api, late_action):
    from fastapi import HTTPException
    from app.auth.router import change_password, delete_user, update_profile
    from app.models import User
    from app.schemas import DeleteUserIn, PasswordChange, ProfilePatch
    from app.security import verify_password
    client, sessions = api
    invite(sessions)
    uid = register(client).json()["user_id"]
    with sessions() as first, sessions() as late:
        first_user = first.get(User, uid)
        late_user = late.get(User, uid)
        rotated = change_password(PasswordChange(current_password="test-password", new_password="first-new-password"), db=first, user=first_user)
        with pytest.raises(HTTPException) as denied:
            if late_action == "password":
                change_password(PasswordChange(current_password="test-password", new_password="stale-new-password"), db=late, user=late_user)
            elif late_action == "rename":
                update_profile(ProfilePatch(username="stale-rename"), db=late, user=late_user)
            else:
                delete_user(DeleteUserIn(current_password="test-password"), db=late, user=late_user)
        assert denied.value.status_code == 401
    with sessions() as db:
        user = db.get(User, uid)
        assert user.auth_version == 1
        assert user.username == "alice"
        assert verify_password("first-new-password", user.password_hash)
    assert client.get("/auth/me", headers={"Authorization": "Bearer " + rotated["access_token"]}).status_code == 200
