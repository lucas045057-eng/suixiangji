from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import os
from threading import Barrier
from uuid import uuid4

import pytest
from sqlalchemy import delete, event, select, update
from sqlalchemy.engine import make_url

from app.db import SessionLocal
from app.models import SyncOperation, Transaction, User
from app.sync.schemas import SyncPushIn
from app.sync.service import pull, push
from integration.postgres_acceptance import isolated_postgres_engine


SKIP_REASON = "real PostgreSQL test requires WEALTHMATE_POSTGRES_TEST_DATABASE_URL"


def _transaction_operation(prefix: str, suffix: str) -> dict:
    return {
        "client_op_id": f"{prefix}:op:{suffix}",
        "entity": "transactions",
        "entity_id": f"{prefix}-tx-{suffix}",
        "type": "upsert",
        "payload": {
            "type": "transfer",
            "amount": "1.00",
            "currency": "CNY",
            "occurred_on": "2026-09-16",
            "note": suffix,
        },
    }


@pytest.fixture
def postgres_case():
    database_url = os.environ.get("WEALTHMATE_POSTGRES_TEST_DATABASE_URL")
    if not database_url:
        pytest.skip(SKIP_REASON)
    if make_url(database_url).get_backend_name() != "postgresql":
        pytest.skip(SKIP_REASON)

    engine = isolated_postgres_engine(
        database_url,
        create_tables=os.environ.get("WEALTHMATE_TEST_SCHEMA_INIT", "").casefold() == "true",
    )
    prefix = f"sync_pg_test_{uuid4().hex}"
    user_id = f"{prefix}_user"
    with SessionLocal(bind=engine) as db:
        db.add(
            User(
                id=user_id,
                username=f"{prefix}_username",
                password_hash="synthetic-postgres-test-only",
                display_name="PostgreSQL concurrency test",
                sync_version=0,
            )
        )
        db.commit()

    try:
        yield engine, prefix, user_id
    finally:
        with SessionLocal(bind=engine) as db:
            db.execute(delete(SyncOperation).where(SyncOperation.user_id == user_id))
            db.execute(delete(Transaction).where(Transaction.user_id == user_id))
            db.execute(delete(User).where(User.id == user_id))
            db.commit()
        engine.dispose()


def test_concurrent_pushes_allocate_unique_versions_and_keep_old_cursor_complete(postgres_case):
    engine, prefix, user_id = postgres_case
    sessions = [SessionLocal(bind=engine), SessionLocal(bind=engine)]
    users = [session.get(User, user_id) for session in sessions]
    assert all(user is not None for user in users)
    payloads = [
        SyncPushIn(operations=[_transaction_operation(prefix, "first")]),
        SyncPushIn(operations=[_transaction_operation(prefix, "second")]),
    ]
    flush_barrier = Barrier(2)

    def pause_both_allocators(_mapper, _connection, target):
        if target.id == user_id:
            flush_barrier.wait(timeout=10)

    event.listen(User, "before_update", pause_both_allocators)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [
                pool.submit(push, payload, session, user)
                for payload, session, user in zip(payloads, sessions, users, strict=True)
            ]
            results = [future.result(timeout=20) for future in futures]
    finally:
        event.remove(User, "before_update", pause_both_allocators)
        for session in sessions:
            session.close()

    accepted_versions = [result["accepted"][0]["server_version"] for result in results]
    old_cursor = min(accepted_versions)
    with SessionLocal(bind=engine) as db:
        owner = db.get(User, user_id)
        rows = db.scalars(
            select(Transaction)
            .where(Transaction.user_id == user_id)
            .order_by(Transaction.server_version, Transaction.id)
        ).all()
        pulled = pull(since_version=old_cursor, db=db, user=owner)

    row_versions = [row.server_version for row in rows]
    pulled_ids = {row["id"] for row in pulled["transactions"]}
    assert sorted(accepted_versions) == [1, 2], (
        f"concurrent pushes allocated {accepted_versions}; database rows={row_versions}; "
        f"old-cursor pull from {old_cursor} returned {sorted(pulled_ids)}"
    )
    assert row_versions == [1, 2]
    assert len(pulled_ids) == 1
    assert owner.sync_version == 2


def test_locked_user_refreshes_stale_identity_map_and_replay_does_not_advance(postgres_case):
    engine, prefix, user_id = postgres_case
    with SessionLocal(bind=engine) as db:
        db.execute(update(User).where(User.id == user_id).values(sync_version=40))
        db.commit()

    allocating_session = SessionLocal(bind=engine)
    replay_session = SessionLocal(bind=engine)
    allocating_user = allocating_session.get(User, user_id)
    replay_user = replay_session.get(User, user_id)
    assert allocating_user.sync_version == replay_user.sync_version == 40

    with SessionLocal(bind=engine) as db:
        db.execute(update(User).where(User.id == user_id).values(sync_version=41))
        db.commit()

    first = _transaction_operation(prefix, "batch-first")
    second = _transaction_operation(prefix, "batch-second")
    try:
        result = push(
            SyncPushIn(operations=[first, second]),
            allocating_session,
            allocating_user,
        )
        replay = push(SyncPushIn(operations=[first]), replay_session, replay_user)
    finally:
        allocating_session.close()
        replay_session.close()

    accepted_versions = [item["server_version"] for item in result["accepted"]]
    with SessionLocal(bind=engine) as db:
        committed_version = db.get(User, user_id).sync_version
        operation_versions = db.scalars(
            select(SyncOperation.server_version)
            .where(SyncOperation.user_id == user_id)
            .order_by(SyncOperation.server_version)
        ).all()

    assert accepted_versions == [42, 43]
    assert accepted_versions == sorted(set(accepted_versions))
    assert operation_versions == [42, 43]
    assert replay["accepted"] == [
        {
            "client_op_id": first["client_op_id"],
            "entity_id": first["entity_id"],
            "server_version": 42,
            "created": False,
        }
    ]
    assert replay["server_version"] == 43
    assert committed_version == 43


def test_failed_push_rolls_back_entity_receipt_and_user_watermark(postgres_case):
    engine, prefix, user_id = postgres_case
    operation = _transaction_operation(prefix, "rollback")
    operation_id = operation["client_op_id"]

    def fail_after_allocation(_mapper, _connection, target):
        if target.user_id == user_id and target.client_op_id == operation_id:
            raise RuntimeError("injected receipt failure")

    session = SessionLocal(bind=engine)
    user = session.get(User, user_id)
    event.listen(SyncOperation, "before_insert", fail_after_allocation)
    try:
        with pytest.raises(RuntimeError, match="injected receipt failure"):
            push(SyncPushIn(operations=[operation]), session, user)
        session.rollback()
    finally:
        event.remove(SyncOperation, "before_insert", fail_after_allocation)
        session.close()

    with SessionLocal(bind=engine) as db:
        assert db.get(Transaction, operation["entity_id"]) is None
        assert db.scalar(
            select(SyncOperation).where(
                SyncOperation.user_id == user_id,
                SyncOperation.client_op_id == operation_id,
            )
        ) is None
        assert db.get(User, user_id).sync_version == 0
