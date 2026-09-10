from datetime import date

import pytest
from sqlalchemy import create_engine, inspect

from test_user_system import api, headers, invite, register


def test_startup_does_not_silently_create_or_alter_schema(tmp_path, monkeypatch):
    import app.models
    from app import db
    from app.config import get_settings
    engine = create_engine(f"sqlite:///{tmp_path / 'unmigrated.db'}")
    monkeypatch.setattr(db, "engine", engine)
    monkeypatch.setenv("WEALTHMATE_TEST_SCHEMA_INIT", "false")
    get_settings.cache_clear()
    try:
        with pytest.raises(RuntimeError, match="alembic upgrade head"):
            db.ensure_schema()
        assert inspect(engine).get_table_names() == []
    finally:
        engine.dispose()
        get_settings.cache_clear()


@pytest.mark.parametrize("overrides", [
    {"jwt_secret": "change-this-before-deployment"},
    {"jwt_secret": "x" * 40, "demo_enabled": True},
    {"jwt_secret": "x" * 40, "test_schema_init": True},
    {"jwt_secret": "x" * 40, "cors_origins": "*"},
])
def test_beta_refuses_unsafe_startup_configuration(overrides):
    from app.config import Settings
    settings = Settings(_env_file=None, environment="beta", cors_origins="https://test.invalid", **{key: value for key, value in overrides.items() if key != "cors_origins"})
    if "cors_origins" in overrides:
        settings.cors_origins = overrides["cors_origins"]
    with pytest.raises(ValueError):
        settings.validate_runtime()


def test_login_and_register_are_rate_limited(api, monkeypatch):
    from app.config import get_settings
    client, _ = api
    monkeypatch.setattr(get_settings(), "auth_login_limit", 2)
    monkeypatch.setattr(get_settings(), "auth_register_limit", 2)
    for _ in range(2):
        assert client.post("/auth/login", json={"username": "absent", "password": "bad"}).status_code == 401
        assert register(client, code="absent").status_code == 400
    for path, body in (("/auth/login", {"username": "absent", "password": "bad"}), ("/auth/register", {"username": "alice", "password": "test-password", "invite_code": "absent"})):
        response = client.post(path, json=body)
        assert response.status_code == 429
        assert int(response.headers["Retry-After"]) > 0


def test_limiter_is_bounded_and_window_expires():
    from app.core.rate_limit import AuthLimiter
    clock = [0.0]
    limiter = AuthLimiter(max_keys=2, window_seconds=60, clock=lambda: clock[0])
    assert limiter.allow("one", 2)
    assert limiter.allow("one", 2)
    assert not limiter.allow("one", 2)
    assert limiter.allow("two", 2)
    assert not limiter.allow("three", 2)
    clock[0] = 61
    assert limiter.allow("three", 2)
    assert limiter.allow("one", 2)


def test_rate_upstream_error_is_sanitized(api, monkeypatch):
    from app import api as routes
    client, sessions = api
    invite(sessions)
    auth = headers(register(client))
    async def unavailable(*_):
        raise RuntimeError("upstream test-secret should not leave server")
    monkeypatch.setattr(routes, "fetch_frankfurter_rate", unavailable)
    response = client.get("/exchange/rates?base=USD", headers=auth)
    assert response.status_code == 502
    assert "test-secret" not in response.text


def test_invalid_schema_response_does_not_echo_password_or_invite(api):
    response = register(api[0], username="!", password="secret", invite_code="test-only-secret-invite")
    assert response.status_code == 422
    assert "test-only-secret" not in response.text
    assert "secret" not in response.text


@pytest.mark.parametrize("scheduled", [False, True])
def test_provider_failure_never_persists_secrets_in_agent_logs(api, monkeypatch, scheduled):
    import asyncio
    from sqlalchemy import select
    from app import api as routes, scheduler
    from app.config import get_settings
    from app.models import AgentLog
    client, sessions = api
    invite(sessions)
    auth = headers(register(client))
    class FailingProvider:
        async def complete(self, *_):
            raise RuntimeError("test-only-api-key-secret https://private.invalid")
    monkeypatch.setattr(get_settings(), "llm_provider", "test-only")
    if scheduled:
        monkeypatch.setattr(scheduler, "SessionLocal", sessions)
        monkeypatch.setattr(scheduler, "configured_model", lambda: FailingProvider())
        asyncio.run(scheduler.run_monthly_report_job())
    else:
        monkeypatch.setattr(routes, "configured_model", lambda: FailingProvider())
        response = client.get("/reports/monthly/2026-09", headers=auth)
        assert response.status_code == 200
        assert "test-only-api-key-secret" not in response.text
    with sessions() as db:
        logs = db.scalars(select(AgentLog)).all()
        assert logs
        assert all("test-only-api-key-secret" not in (row.result_summary or "") for row in logs)


def test_database_errors_do_not_include_sensitive_sql_parameters(monkeypatch):
    from sqlalchemy import text
    from sqlalchemy.exc import SQLAlchemyError
    from app.config import get_settings
    from app.db import _engine
    monkeypatch.setenv("WEALTHMATE_DATABASE_URL", "sqlite:///:memory:")
    get_settings.cache_clear()
    engine = _engine()
    try:
        with engine.connect() as db:
            with pytest.raises(SQLAlchemyError) as failure:
                db.execute(text("SELECT code FROM missing_test_table WHERE code=:code"), {"code": "test-only-invitation-secret"})
        assert "test-only-invitation-secret" not in str(failure.value)
    finally:
        engine.dispose()
        get_settings.cache_clear()


def test_readonly_database_registration_failure_is_sanitized(api):
    from sqlalchemy import event
    client, sessions = api
    invite(sessions)
    engine = sessions.kw["bind"]
    def readonly(dbapi_connection, record, proxy):
        dbapi_connection.execute("PRAGMA query_only=ON")
    event.listen(engine, "checkout", readonly)
    try:
        response = register(client)
        assert response.status_code == 503
        assert "test-only-invite" not in response.text
        assert "SQL" not in response.text
    finally:
        event.remove(engine, "checkout", readonly)
