import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db import Base, SessionLocal
from app.models import Budget, Transaction, User
from app.budget.service import update_budget
from app.budget.schemas import BudgetPatch
from app.sync.schemas import SyncPushIn
from app.sync.service import push
from test_sync_postgres_concurrency import postgres_case, _transaction_operation


def budget_operation(entity_id, month='2026-10'):
    return dict(client_op_id=f'{entity_id}-op', entity='budgets',
                entity_id=entity_id, type='upsert',
                payload=dict(month=month, category_id='__total__', limit=100))


def test_legacy_offline_budget_collision_keeps_other_batch_writes_and_original_id():
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as db:
        user = User(id='review-owner', username='review-owner', password_hash='synthetic')
        db.add(user)
        db.commit()
        push(SyncPushIn(operations=[budget_operation('device-a')]), db, user)
        transaction = dict(client_op_id='bill-op', entity='transactions', entity_id='bill',
                           type='upsert', payload=dict(type='transfer', amount=1,
                                                      currency='CNY', occurred_on='2026-10-09'))
        result = push(SyncPushIn(operations=[budget_operation('device-b'), transaction]), db, user)
        assert [row['entity_id'] for row in result['accepted']] == ['bill']
        assert result['conflicts'][0]['canonical_entity_id'] == 'device-a'
        assert db.query(Budget).one().id == 'device-a'
        assert db.get(Transaction, 'bill') is not None
        assert user.sync_version == 2
        replay = push(SyncPushIn(operations=[budget_operation('device-b'), transaction]), db, user)
        assert replay['server_version'] == 2
        push(SyncPushIn(operations=[budget_operation('other-month', '2026-09')]), db, user)
        with pytest.raises(HTTPException) as exc:
            update_budget(db, user, 'other-month', BudgetPatch(month='2026-10'))
        assert exc.value.status_code == 409
        db.rollback()
        assert db.get(Budget, 'other-month').month == '2026-09'
    engine.dispose()


def test_real_postgres_waiting_old_push_is_rejected_after_password_recovery(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event
    from sqlalchemy import event
    from app.auth.service import recover_password
    from app.auth.schemas import PasswordRecoverIn
    from app.core.security import hash_password

    engine, prefix, user_id = postgres_case
    with SessionLocal(bind=engine) as db:
        user = db.get(User, user_id)
        user.recovery_code_hash = hash_password('A' * 48)
        username = user.username
        db.commit()
    old_session = SessionLocal(bind=engine)
    old_user = old_session.get(User, user_id)
    waiting = Event()
    def reached_lock(_conn, _cursor, statement, _parameters, _context, _many):
        if 'FOR UPDATE' in statement:
            waiting.set()
    event.listen(engine, 'before_cursor_execute', reached_lock)
    operation = _transaction_operation(prefix, 'old-auth')
    try:
        with SessionLocal(bind=engine) as resetting, ThreadPoolExecutor(max_workers=1) as pool:
            resetting.query(User).filter(User.id == user_id).with_for_update().one()
            waiting.clear()
            future = pool.submit(push, SyncPushIn(operations=[operation]), old_session, old_user)
            assert waiting.wait(timeout=10)
            recover_password(resetting, PasswordRecoverIn(username=username,
                recovery_code='A' * 48, new_password='new-synthetic-password'))
            with pytest.raises(HTTPException) as exc:
                future.result(timeout=15)
            assert exc.value.status_code == 401
    finally:
        event.remove(engine, 'before_cursor_execute', reached_lock)
        old_session.close()
    with SessionLocal(bind=engine) as db:
        assert db.get(Transaction, operation['entity_id']) is None
        assert db.get(User, user_id).sync_version == 0


def test_real_postgres_concurrent_budget_creation_preserves_both_batches(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from sqlalchemy import delete

    engine, prefix, user_id = postgres_case
    start = Barrier(2)
    def upload(suffix):
        with SessionLocal(bind=engine) as db:
            user = db.get(User, user_id)
            start.wait(timeout=10)
            return push(SyncPushIn(operations=[
                budget_operation(f'{prefix}-{suffix}'),
                _transaction_operation(prefix, suffix),
            ]), db, user)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(upload, ['a', 'b']))
        assert sorted(len(r['accepted']) for r in results) == [1, 2]
        assert sorted(len(r['conflicts']) for r in results) == [0, 1]
        with SessionLocal(bind=engine) as db:
            assert db.query(Budget).filter(Budget.user_id == user_id).count() == 1
            assert db.query(Transaction).filter(Transaction.user_id == user_id).count() == 2
            assert db.get(User, user_id).sync_version == 3
    finally:
        with SessionLocal(bind=engine) as db:
            db.execute(delete(Budget).where(Budget.user_id == user_id))
            db.commit()


def test_mutating_auth_resolution_refreshes_stale_user_before_checking_token():
    from app.auth.service import get_current_user
    from app.core.security import create_token
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as stale, Session(engine) as reset:
        user = User(id='auth-review', username='auth-review', password_hash='synthetic')
        stale.add(user)
        stale.commit()
        token = create_token(user.id, user.username, user.auth_version)
        current = reset.get(User, user.id)
        current.auth_version += 1
        reset.commit()
        with pytest.raises(HTTPException) as exc:
            get_current_user(stale, token, for_update=True)
        assert exc.value.status_code == 401
    engine.dispose()
