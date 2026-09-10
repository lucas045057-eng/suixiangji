"""Migration contract uses legacy SQL fixtures, never current create_all."""
import os
from pathlib import Path
import subprocess
import sys

import pytest
from sqlalchemy import create_engine, inspect, text


def upgrade(url):
    env = {**os.environ, "WEALTHMATE_DATABASE_URL": url, "PYTHONIOENCODING": "utf-8"}
    return subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=Path(__file__).resolve().parents[1], env=env, capture_output=True, text=True, encoding="utf-8", timeout=60)


def legacy_user(connection, username="Legacy-User", identifier="legacy"):
    from app.security import hash_password
    connection.execute(text("CREATE TABLE IF NOT EXISTS users (id VARCHAR(64) PRIMARY KEY, username VARCHAR(128) NOT NULL UNIQUE, password_hash VARCHAR(256) NOT NULL, sync_version INTEGER NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"))
    connection.execute(text("INSERT INTO users (id, username, password_hash, sync_version) VALUES (:id,:name,:hash,42)"), {"id": identifier, "name": username, "hash": hash_password("legacy-test-password")})


def test_empty_database_initializes_via_migration(tmp_path):
    url = f"sqlite:///{tmp_path / 'empty.db'}"
    result = upgrade(url)
    assert result.returncode == 0, result.stderr
    engine = create_engine(url)
    assert {"users", "invite_codes", "transactions", "sync_operations", "alembic_version"} <= set(inspect(engine).get_table_names())
    assert upgrade(url).returncode == 0
    engine.dispose()


def test_legacy_upgrade_retains_login_finances_and_sync_versions(tmp_path):
    from app.models import Account, Transaction
    from app.db import Base
    from app.security import verify_password
    from sqlalchemy.orm import Session
    from app.models import User
    url = f"sqlite:///{tmp_path / 'legacy.db'}"
    engine = create_engine(url)
    with engine.begin() as connection:
        legacy_user(connection)
        # Account/transaction schema at the approved starting revision, with
        # pre-existing monetary and sync data. User predates additive columns.
        connection.execute(text("CREATE TABLE accounts (id VARCHAR(64) PRIMARY KEY, user_id VARCHAR(64) NOT NULL REFERENCES users(id), name VARCHAR(128) NOT NULL, kind VARCHAR(32) NOT NULL, currency VARCHAR(16) NOT NULL, opening_balance NUMERIC(20,6) NOT NULL, opening_cny_amount NUMERIC(20,6), opening_exchange_rate NUMERIC(20,10), opening_rate_date DATE, opening_rate_source VARCHAR(256), deleted_at TIMESTAMP, server_version INTEGER NOT NULL)"))
        connection.execute(text("INSERT INTO accounts (id,user_id,name,kind,currency,opening_balance,server_version) VALUES ('legacy-account','legacy','old account','asset','CNY',123,40)"))
        connection.execute(text("CREATE TABLE transactions (id VARCHAR(64) PRIMARY KEY, user_id VARCHAR(64) NOT NULL REFERENCES users(id), client_op_id VARCHAR(128) NOT NULL, kind VARCHAR(32) NOT NULL, amount NUMERIC(20,6) NOT NULL, currency VARCHAR(16) NOT NULL, cny_amount NUMERIC(20,6), exchange_rate NUMERIC(20,10), exchange_rate_date DATE, exchange_rate_source VARCHAR(256), conversion_status VARCHAR(32) NOT NULL, category_id VARCHAR(64), category_name VARCHAR(128), account_id VARCHAR(64) REFERENCES accounts(id), from_account_id VARCHAR(64), to_account_id VARCHAR(64), occurred_on DATE NOT NULL, note TEXT, deleted_at TIMESTAMP, server_version INTEGER NOT NULL, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"))
        connection.execute(text("INSERT INTO transactions (id,user_id,client_op_id,kind,amount,currency,cny_amount,conversion_status,account_id,occurred_on,server_version) VALUES ('legacy-tx','legacy','legacy-op','expense',12,'CNY',12,'ready','legacy-account','2026-09-01',42)"))
    result = upgrade(url)
    assert result.returncode == 0, result.stderr
    with Session(engine) as db:
        user = db.get(User, "legacy")
        assert user.username == "Legacy-User"
        assert verify_password("legacy-test-password", user.password_hash)
        assert user.sync_version == 42
        assert user.auth_version == 0
        assert db.get(Account, "legacy-account").opening_balance == 123
        assert db.get(Account, "legacy-account").server_version == 40
        assert db.get(Transaction, "legacy-tx").amount == 12
        assert db.get(Transaction, "legacy-tx").server_version == 42
        assert db.get(Transaction, "legacy-tx").client_op_id == "legacy-op"
    engine.dispose()


def test_username_collision_aborts_without_discarding_records(tmp_path):
    url = f"sqlite:///{tmp_path / 'collision.db'}"
    engine = create_engine(url)
    with engine.begin() as connection:
        legacy_user(connection, "Alice", "one")
        legacy_user(connection, " alice ", "two")
    result = upgrade(url)
    assert result.returncode != 0
    assert "collision" in result.stderr.lower()
    with engine.connect() as connection:
        assert connection.execute(text("SELECT count(*) FROM users")).scalar() == 2
        assert connection.execute(text("SELECT sum(sync_version) FROM users")).scalar() == 84
    engine.dispose()

