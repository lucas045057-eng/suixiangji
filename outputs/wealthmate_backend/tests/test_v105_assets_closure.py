from datetime import date
from decimal import Decimal

from fastapi import HTTPException
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db import Base
from app.models import ExchangeRate, Transaction, User
from app.assets.schemas import AccountIn
from app.assets.service import account_json, exchange_rate, save_account
from app.sync.schemas import SyncPushIn
from app.sync.service import pull, push


@pytest.fixture
def db():
    engine = create_engine('sqlite:///:memory:')
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as session:
        session.add(User(id='v105-owner', username='v105-owner',
            password_hash='synthetic-only', sync_version=0))
        session.commit()
        yield session
    engine.dispose()


def account_operation(op_id, **extra):
    return dict(client_op_id=op_id, entity='accounts', entity_id='v105-hkd',
        type='upsert', payload=dict(name='港币账户',currency='HKD',
            opening_balance=100, **extra))


def test_archive_restore_sync_retains_history_and_purpose(db):
    owner = db.get(User, 'v105-owner')
    push(SyncPushIn(operations=[account_operation('initial', note='工资卡')]),db,owner)
    db.add(Transaction(id='bill',user_id=owner.id,client_op_id='bill-op',kind='expense',
        amount=10,currency='HKD',account_id='v105-hkd',occurred_on=date(2026,9,1),server_version=1))
    db.commit()
    push(SyncPushIn(operations=[account_operation('archive',
        note='工资卡',archived_at='2026-10-09T10:00:00',server_version=1)]),db,owner)
    archived = pull(0,db,owner)['accounts'][0]
    assert archived.get('archived_at') is not None
    assert archived['deleted_at'] is None
    assert archived['note'] == '工资卡'
    assert db.get(Transaction,'bill').account_id == 'v105-hkd'
    push(SyncPushIn(operations=[account_operation('restore',
        archived_at=None,server_version=2)]),db,owner)
    restored = pull(2,db,owner)['accounts'][0]
    assert restored['archived_at'] is None
    assert restored['note'] == '工资卡'  # old clients omitting note must not erase it
    assert db.get(Transaction,'bill').amount == 10


def test_account_input_preserves_optional_lifecycle_fields():
    data = AccountIn(name='工资卡', note='日常用途',archived_at='2026-10-09T10:00:00').model_dump()
    assert data.get('note') == '日常用途'
    assert data.get('archived_at') is not None


def test_old_payload_does_not_erase_new_fields(db):
    user = db.get(User,'v105-owner')
    row = save_account(db,user,dict(id='a',name='卡',note='用途',archived_at='2026-10-09T10:00:00'))
    db.commit()
    row = save_account(db,user,dict(id='a',name='新名'))
    db.commit()
    data = account_json(row)
    assert data.get('note') == '用途'
    assert data.get('archived_at') is not None


def test_rate_failure_returns_dated_cache_without_fabricating_fresh_success(db,monkeypatch):
    import asyncio
    db.add(ExchangeRate(base_currency='HKD',quote_currency='CNY',rate=Decimal('.9'),
        rate_date=date(2026,10,8),source='Frankfurter v2'))
    db.commit()
    async def offline(*_args):
        raise TimeoutError('synthetic outage')
    monkeypatch.setattr('app.assets.service.fetch_frankfurter_rate',offline)
    result = asyncio.run(exchange_rate(db,db.get(User,'v105-owner'),'HKD'))
    assert result['rate'] == .9
    assert result['rate_date'] == '2026-10-08'
    assert result['stale'] is True
    with pytest.raises(HTTPException) as error:
        asyncio.run(exchange_rate(db,db.get(User,'v105-owner'),'USD'))
    assert error.value.status_code == 502


def test_v104_database_upgrades_without_changing_identifiers_or_amounts(tmp_path):
    import os,subprocess,sys
    from pathlib import Path
    from sqlalchemy import text,inspect
    url=f'sqlite:///{tmp_path / "upgrade.db"}'
    env={**os.environ,'WEALTHMATE_DATABASE_URL':url,'PYTHONIOENCODING':'utf-8'}
    cwd=Path(__file__).resolve().parents[1]
    first=subprocess.run([sys.executable,'-m','alembic','upgrade','0002_beta_users'],cwd=cwd,env=env,capture_output=True,text=True)
    assert first.returncode==0,first.stderr
    engine=create_engine(url)
    with engine.begin() as connection:
        connection.execute(text("INSERT INTO users(id,username,password_hash,display_name,quick_memories,auth_version,sync_version) VALUES ('old','old','test','Old','[]',0,42)"))
        connection.execute(text("INSERT INTO accounts(id,user_id,name,kind,account_kind,currency,opening_balance,is_liquid,is_default_payment,server_version) VALUES ('old-card','old','Old card','asset','other','HKD',123,0,0,40)"))
    result=subprocess.run([sys.executable,'-m','alembic','upgrade','head'],cwd=cwd,env=env,capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    assert {'note','archived_at'} <= {c['name'] for c in inspect(engine).get_columns('accounts')}
    with engine.connect() as connection:
        assert connection.execute(text("SELECT id,opening_balance,server_version FROM accounts")).one()==('old-card',123,40)
        assert connection.execute(text("SELECT sync_version FROM users")).scalar()==42
    engine.dispose()
