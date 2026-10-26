from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import os
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import delete, select
from sqlalchemy.engine import make_url

from app.backup.schemas import RestoreIn
from app.backup.service import restore_backup
from app.db import SessionLocal
from app.models import (
    Account,
    Budget,
    Category,
    MonthlyReport,
    NetWorthSnapshot,
    SyncOperation,
    Transaction,
    User,
)
from integration.postgres_acceptance import isolated_postgres_engine


SKIP_REASON = "real PostgreSQL restore concurrency requires WEALTHMATE_POSTGRES_TEST_DATABASE_URL"


@pytest.fixture
def restore_postgres_case():
    database_url = os.environ.get("WEALTHMATE_POSTGRES_TEST_DATABASE_URL")
    if not database_url or make_url(database_url).get_backend_name() != "postgresql":
        pytest.skip(SKIP_REASON)
    engine = isolated_postgres_engine(
        database_url,
        create_tables=os.environ.get("WEALTHMATE_TEST_SCHEMA_INIT", "").casefold() == "true",
    )
    prefix = f"backup_pg_test_{uuid4().hex}"
    user_id = f"{prefix}_user"
    with SessionLocal(bind=engine) as db:
        db.add(
            User(
                id=user_id,
                username=f"{prefix}_username",
                password_hash="synthetic-postgres-test-only",
                display_name="PostgreSQL backup concurrency test",
                sync_version=0,
            )
        )
        db.commit()
    try:
        yield engine, user_id, prefix
    finally:
        with SessionLocal(bind=engine) as db:
            for model in (
                Transaction,
                Budget,
                SyncOperation,
                NetWorthSnapshot,
                MonthlyReport,
                Account,
                Category,
                User,
            ):
                db.execute(delete(model).where(model.user_id == user_id))
            db.commit()
        engine.dispose()


def _payload(user_id: str, restore_id: str, account_id: str) -> RestoreIn:
    return RestoreIn(
        kind="suixiangji.backup",
        schema_version=2,
        owner_id=user_id,
        restore_id=restore_id,
        accounts=[
            {
                "id": account_id,
                "name": account_id,
                "kind": "asset",
                "currency": "CNY",
                "opening_balance": "1.000000",
                "deleted_at": None,
            }
        ],
    )


def _concurrent_restore(payloads, engine, user_id):
    sessions = [SessionLocal(bind=engine), SessionLocal(bind=engine)]
    users = [session.get(User, user_id) for session in sessions]
    barrier = Barrier(2)

    def run(payload, session, user):
        barrier.wait(timeout=10)
        return restore_backup(payload, session, user)

    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [
                pool.submit(run, payload, session, user)
                for payload, session, user in zip(payloads, sessions, users, strict=True)
            ]
            return [future.result(timeout=30) for future in futures]
    finally:
        for session in sessions:
            session.close()


def test_concurrent_distinct_restores_serialize_versions(restore_postgres_case):
    engine, user_id, prefix = restore_postgres_case
    results = _concurrent_restore(
        [
            _payload(user_id, "restore-a", f"{prefix}-account-a"),
            _payload(user_id, "restore-b", f"{prefix}-account-b"),
        ],
        engine,
        user_id,
    )
    assert sorted(result["server_version"] for result in results) == [1, 2]
    with SessionLocal(bind=engine) as db:
        user = db.get(User, user_id)
        rows = db.scalars(
            select(Account)
            .where(Account.user_id == user_id)
            .order_by(Account.server_version)
        ).all()
        assert user.sync_version == 2
        assert [row.server_version for row in rows] == [1, 2]


def test_concurrent_same_restore_id_writes_one_receipt(restore_postgres_case):
    engine, user_id, prefix = restore_postgres_case
    results = _concurrent_restore(
        [
            _payload(user_id, "restore-once", f"{prefix}-account"),
            _payload(user_id, "restore-once", f"{prefix}-account"),
        ],
        engine,
        user_id,
    )
    assert sorted(result["replayed"] for result in results) == [False, True]
    with SessionLocal(bind=engine) as db:
        assert db.get(User, user_id).sync_version == 1
        assert db.scalar(
            select(SyncOperation).where(
                SyncOperation.user_id == user_id,
                SyncOperation.client_op_id == "restore:restore-once",
            )
        ) is not None
        assert db.scalar(select(Account).where(Account.user_id == user_id)) is not None
