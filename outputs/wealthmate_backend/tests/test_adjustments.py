from datetime import date, timedelta
from decimal import Decimal
import importlib.util
from pathlib import Path
import pytest
from fastapi import FastAPI, Depends
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError
from alembic import command
from alembic.config import Config
from alembic.operations import Operations
from alembic.migration import MigrationContext
from app.db import Base, get_db
from app.models import Account, Transaction, SyncOperation, User
from app.core.dependencies import get_current_user
from app.assets.router import router as assets
from app.ledger.router import router as ledger
from app.sync.router import router as sync
from app.insights.router import router as insights
from app.backup.router import router as backup
from app.assets.schemas import CalibrationIn, ReverseCalibrationIn
from app.assets.calibration import calibrate, reverse
from app.ledger.schemas import AdjustmentIn
from app.ledger.domain import normalise_transaction_payload

D=date(2026,9,1)
H={"X-Wealthmate-Sync-Protocol":"2"}

@pytest.fixture
def api(tmp_path):
    engine=create_engine(f"sqlite:///{tmp_path/'adjustments.db'}",connect_args={"check_same_thread":False})
    event.listen(engine,"connect",lambda c,_: c.execute("PRAGMA foreign_keys=ON"))
    Base.metadata.create_all(engine)
    sessions=sessionmaker(engine,expire_on_commit=False,autoflush=False)
    with sessions.begin() as db:
        db.add(User(id="u",username="u",password_hash="synthetic",sync_version=0))
        db.add(User(id="other",username="other",password_hash="synthetic",sync_version=0))
    app=FastAPI()
    for router in (assets,ledger,sync,insights,backup):app.include_router(router)
    def database():
        with sessions() as db:yield db
    def owner(db=Depends(get_db)):return db.get(User,"u")
    app.dependency_overrides[get_db]=database
    app.dependency_overrides[get_current_user]=owner
    with TestClient(app) as client:yield client,sessions
    engine.dispose()

def account(client,identifier="a",**values):
    response=client.post("/accounts",json=dict(id=identifier,name=identifier,opening_balance=100,**values))
    assert response.status_code==200,response.text

def payload(identifier="adjust",**values):
    return dict(client_op_id=identifier+"-op",adjustment_id=identifier,target_cny="125.00",
        expected_current_cny="100",effective_on=D.isoformat(),**values)

def post(client,identifier="adjust",account_id="a",**values):
    return client.post(f"/assets/accounts/{account_id}/calibration",json=payload(identifier,**values))

def test_calibrate_exact_replay_and_legacy_views(api):
    client,sessions=api;account(client)
    result=post(client);assert result.status_code==200,result.text
    row=result.json();assert row['kind']=='adjustment' and Decimal(row['amount'])==25
    assert Decimal(row['cny_amount'])==25 and Decimal(row['exchange_rate'])==1
    assert row['adjustment_meta']['basis_balance_cny']=='100.000000'
    assert post(client).json()==row
    for route,key in [('/sync/pull','transactions'),('/transactions','items')]:
        assert client.get(route).json()[key]==[]
        assert client.get(route,headers=H).json()[key][0]['id']=='adjust'
    assert client.get('/wealth').json()['net_worth']==100
    assert client.get('/wealth',headers=H).json()['net_worth']==125
    assert client.get('/wealth?as_of_date=2026-08-31',headers=H).json()['net_worth']==100
    with sessions() as db:
        assert db.query(Transaction).count()==1 and db.query(SyncOperation).count()==1
        assert db.get(Account,'a').opening_balance==100
    altered=payload();altered['target_cny']='126'
    assert client.post('/assets/accounts/a/calibration',json=altered).json()['code']=='operation_mismatch'

def test_stale_expected_and_zero_delta_write_nothing(api):
    client,sessions=api;account(client)
    for expected,target,code in [('99','125','balance_changed'),('100','100','balance_unchanged')]:
        p=payload();p.update(expected_current_cny=expected,target_cny=target)
        before=client.get('/sync/pull').json()['server_version']
        response=client.post('/assets/accounts/a/calibration',json=p)
        assert response.status_code==409 and response.json()['code']==code
        with sessions() as db:
            assert db.query(Transaction).count()==db.query(SyncOperation).count()==0
            assert db.get(User,'u').sync_version==before

def test_reverse_unique_replay_and_date_rules(api):
    client,sessions=api;account(client);assert post(client).status_code==200
    reverse_url='/assets/accounts/a/calibrations/adjust/reverse'
    p=dict(client_op_id='reverse-op',adjustment_id='reverse',effective_on='2026-09-02')
    response=client.post(reverse_url,json=p)
    assert response.status_code==200,response.text
    row=response.json();assert Decimal(row['amount'])==-25 and row['reverses_transaction_id']=='adjust'
    assert client.post(reverse_url,json=p).json()==row
    duplicate={**p,'client_op_id':'another-op','adjustment_id':'another'}
    assert client.post(reverse_url,json=duplicate).json()['code']=='already_reversed'
    url='/assets/accounts/a/calibrations/reverse/reverse'
    assert client.post(url,json=duplicate).json()['code']=='not_reversible'
    assert client.get('/wealth?as_of_date=2026-09-01',headers=H).json()['net_worth']==125
    assert client.get('/wealth?as_of_date=2026-09-02',headers=H).json()['net_worth']==100
    with sessions() as db:
        assert db.query(Transaction).count()==2 and db.query(SyncOperation).count()==2
        original=db.get(Transaction,'adjust')
        duplicate_row=Transaction(id='db-duplicate',user_id='u',client_op_id='db-op',kind='adjustment',
            amount=-25,cny_amount=-25,currency='CNY',exchange_rate=1,conversion_status='ready',
            account_id='a',occurred_on=D,adjustment_meta={'reason':'reversal'},reverses_transaction_id=original.id)
        db.add(duplicate_row)
        with pytest.raises(IntegrityError):db.commit()

def test_asset_liability_signs_and_reports_exclude_adjustments(api):
    client,sessions=api;account(client,'asset');account(client,'debt',kind='liability')
    assert post(client,'asset-adjust','asset').status_code==200
    assert post(client,'debt-adjust','debt').status_code==200
    w=client.get('/wealth',headers=H).json()
    assert w['total_assets']==125 and w['total_liabilities']==125 and w['net_worth']==0
    stats=client.get('/stats?month=2026-09').json()
    assert stats['income']==stats['expense']==stats['savings_rate']==0
    assert stats['category_totals']=={} and not stats['data_sufficient']
    assert stats['expense_total']==stats['net_worth_change']==0
    assert stats['pending_conversion_count']==0
    assert client.get('/backup/export').status_code==409

def test_fractional_history_delta_is_not_rounded(api):
    client,sessions=api;account(client)
    with sessions.begin() as db:
        a=db.get(Account,'a');a.opening_balance=Decimal('100.123456')
    p=payload();p.update(expected_current_cny='100.123456',target_cny='101.00')
    response=client.post('/assets/accounts/a/calibration',json=p)
    assert response.status_code==200,response.text
    assert Decimal(response.json()['amount'])==Decimal('.876544')
    assert client.get('/wealth',headers=H).json()['net_worth']==101

@pytest.mark.parametrize('field,value',[('target_cny','NaN'),('target_cny','Infinity'),
    ('target_cny','1.001'),('expected_current_cny','1.0000001'),('target_cny','100000000000000'),
    ('effective_on',123),('effective_on','bad'),('effective_on',(date.today()+timedelta(days=1)).isoformat())])
def test_invalid_schema(api,field,value):
    client,_=api;account(client);p=payload();p[field]=value
    assert client.post('/assets/accounts/a/calibration',json=p).status_code==422

@pytest.mark.parametrize('field,value',[('amount',0),('cny_amount',3),('currency','USD'),
    ('exchange_rate',2),('category_id','c'),('from_account_id','a')])
def test_adjustment_schema_invariants(field,value):
    data=dict(id='adj',client_op_id='op',amount=2,cny_amount=2,account_id='a',occurred_on=D,adjustment_meta={'reason':'balance_calibration'})
    data[field]=value
    with pytest.raises(ValueError):AdjustmentIn(**data)

def test_ordinary_rest_and_sync_cannot_forge_edit_or_delete(api):
    client,sessions=api;account(client);assert post(client).status_code==200
    ordinary=dict(id='adjust',client_op_id='edit',kind='income',amount=1,account_id='a',occurred_on=D.isoformat())
    assert client.patch('/transactions/adjust',json=ordinary).status_code==422
    assert client.delete('/transactions/adjust').status_code==422
    forged={**ordinary,'id':'forged','kind':'adjustment'}
    assert client.post('/transactions',json=forged).status_code==422
    operations=[dict(entity='transactions',entity_id='adjust',client_op_id='delete-op',type='delete',payload=ordinary)]
    before=client.get('/sync/pull',headers=H).json()['server_version']
    assert client.post('/sync/push',json={'operations':operations}).status_code==422
    assert client.get('/sync/pull',headers=H).json()['server_version']==before
    with sessions() as db:assert db.get(Transaction,'adjust').deleted_at is None
    forged['adjustment_meta']={'reason':'forgery'}
    operations[0].update(entity_id='forged',client_op_id='forged-op',type='upsert',payload=forged)
    assert client.post('/sync/push',json={'operations':operations}).status_code==422

def test_account_ownership_inactive_and_missing_conversion(api):
    client,sessions=api;account(client)
    with sessions.begin() as db:db.get(Account,'a').user_id='other'
    assert post(client).status_code==404
    with sessions.begin() as db:
        a=db.get(Account,'a');a.user_id='u';a.archived_at=__import__('datetime').datetime(2026,9,1)
    assert post(client).json()['code']=='account_inactive'
    with sessions.begin() as db:
        a=db.get(Account,'a');a.archived_at=None;a.currency='USD';a.opening_cny_amount=None
    assert post(client).json()['code']=='conversion_pending'

def test_normalizer_retains_signed_precision_without_fx():
    from app.ledger.service import attach_latest_rate
    values=dict(kind='adjustment',amount='-0.123456',cny_amount='-0.123456',exchange_rate='1',currency='CNY',adjustment_meta={'reason':'reversal'})
    assert attach_latest_rate(None,values) is values
    result=normalise_transaction_payload(values)
    assert result['amount']==result['cny_amount']==Decimal('-.123456')
    assert result['adjustment_meta']==values['adjustment_meta']

def test_database_check_rejects_invalid_adjustment(api):
    client,sessions=api;account(client)
    with sessions() as db:
        db.add(Transaction(id='invalid',user_id='u',client_op_id='invalid',kind='adjustment',amount=0,cny_amount=0,
            currency='CNY',exchange_rate=1,conversion_status='ready',account_id='a',occurred_on=D,adjustment_meta={}))
        with pytest.raises(IntegrityError):db.commit()

def test_migration_0005_to_0006_replay_preserves_finances(tmp_path,monkeypatch):
    from app.config import get_settings
    monkeypatch.setenv('WEALTHMATE_DATABASE_URL',f"sqlite:///{tmp_path/'migration.db'}")
    get_settings.cache_clear();root=Path(__file__).resolve().parents[1]
    cfg=Config(str(root/'alembic.ini'))
    command.upgrade(cfg,'0005_v110_account_safety')
    engine=create_engine(f"sqlite:///{tmp_path/'migration.db'}")
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,username,password_hash,display_name,quick_memories,auth_version,sync_version) VALUES ('u','u','x','u','[]',0,42)"))
        c.execute(text("INSERT INTO accounts(id,user_id,name,normalized_name,kind,account_kind,currency,opening_balance,is_liquid,is_default_payment,server_version) VALUES ('a','u','a','a','asset','other','CNY',100,0,0,40)"))
        c.execute(text("INSERT INTO transactions(id,user_id,client_op_id,kind,amount,currency,cny_amount,account_id,occurred_on,conversion_status,server_version) VALUES ('t','u','t','expense',1.123456,'CNY',1.123456,'a','2026-09-01','ready',42)"))
    command.upgrade(cfg,'head')
    spec=importlib.util.spec_from_file_location('adjustment_migration',root/'migrations/versions/0006_v110_adjustments.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with engine.begin() as c:
        before=c.execute(text('SELECT id,amount,cny_amount,account_id,server_version FROM transactions')).all()
        with Operations.context(MigrationContext.configure(c)):module.upgrade()
        assert c.execute(text('SELECT id,amount,cny_amount,account_id,server_version FROM transactions')).all()==before
        assert abs(before[0][1]-1.123456)<1e-10 and before[0][3:] == ('a',42)
        assert c.execute(text('SELECT sync_version FROM users')).scalar()==42
        assert c.execute(text('SELECT adjustment_meta,reverses_transaction_id FROM transactions')).one()==(None,None)
    engine.dispose();get_settings.cache_clear()


@pytest.mark.parametrize('target',['0.00','-25.50'])
def test_signed_targets_are_valid(api,target):
    client,_=api;account(client);p=payload();p['target_cny']=target
    response=client.post('/assets/accounts/a/calibration',json=p)
    assert response.status_code==200,response.text
    assert client.get('/wealth',headers=H).json()['net_worth']==float(target)


def test_reverse_cannot_predate_original_or_cross_accounts(api):
    client,_=api;account(client);account(client,'b');assert post(client).status_code==200
    p=dict(client_op_id='reverse-op',adjustment_id='reverse',effective_on='2026-08-31')
    assert client.post('/assets/accounts/a/calibrations/adjust/reverse',json=p).status_code==422
    p['effective_on']='2026-09-01'
    assert client.post('/assets/accounts/b/calibrations/adjust/reverse',json=p).status_code==404


from test_sync_postgres_concurrency import postgres_case


def test_postgres_calibration_and_reversal_races(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from sqlalchemy import delete
    from app.db import SessionLocal
    from app.assets.service import create_account
    from app.assets.schemas import AccountIn
    from fastapi import HTTPException
    engine,prefix,user_id=postgres_case
    aid=prefix+'a'
    with SessionLocal(bind=engine) as db:
        create_account(db,db.get(User,user_id),AccountIn(id=aid,name=aid,opening_balance=100))
    start=Barrier(2)
    def submit(suffix):
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            command=CalibrationIn(client_op_id=prefix+suffix,adjustment_id=prefix+suffix,
                target_cny=125,expected_current_cny=100,effective_on=D)
            start.wait(timeout=10)
            try:return calibrate(db,user,aid,command)
            except HTTPException as exc:
                assert exc.status_code==409 and exc.detail['code']=='balance_changed'
                return None
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(submit,['a','b']))
        assert sum(r is not None for r in results)==1
        original=next(r for r in results if r is not None)
        start=Barrier(2)
        def undo(suffix):
            with SessionLocal(bind=engine) as db:
                user=db.get(User,user_id)
                command=ReverseCalibrationIn(client_op_id=prefix+'r'+suffix,adjustment_id=prefix+'r'+suffix,effective_on=D)
                start.wait(timeout=10)
                try:return reverse(db,user,aid,original['id'],command)
                except HTTPException as exc:
                    assert exc.status_code==409 and exc.detail['code']=='already_reversed'
                    return None
        with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(undo,['a','b']))
        assert sum(r is not None for r in results)==1
        with SessionLocal(bind=engine) as db:
            assert db.query(Transaction).filter_by(user_id=user_id).count()==2
            assert db.query(SyncOperation).filter_by(user_id=user_id).count()==2
            assert db.get(User,user_id).sync_version==3
    finally:
        with SessionLocal(bind=engine) as db:
            db.execute(delete(Transaction).where(Transaction.user_id==user_id))
            db.execute(delete(Account).where(Account.user_id==user_id))
            db.commit()


def test_postgres_0006_rerun_preserves_storage(postgres_case):
    engine,prefix,user_id=postgres_case
    root=Path(__file__).resolve().parents[1]
    spec=importlib.util.spec_from_file_location('pg_adjustment_migration',root/'migrations/versions/0006_v110_adjustments.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with engine.begin() as c:
        before=c.execute(text('SELECT id,sync_version FROM users ORDER BY id')).all()
        with Operations.context(MigrationContext.configure(c)):module.upgrade()
        assert c.execute(text('SELECT id,sync_version FROM users ORDER BY id')).all()==before
        assert c.execute(text('SELECT version_num FROM alembic_version')).scalar()=='0007_v110_sync_v2'


def test_reverse_retry_without_explicit_date_returns_original_after_day_change(api):
    client,sessions=api;account(client);assert post(client).status_code==200
    command=ReverseCalibrationIn(client_op_id='undo-default-date',adjustment_id='undo-default-date')
    with sessions() as db:original=reverse(db,db.get(User,'u'),'a','adjust',command)
    # Decode the same wire fields on a later day, when the server default changes.
    later=ReverseCalibrationIn.model_construct(client_op_id=command.client_op_id,
        adjustment_id=command.adjustment_id,effective_on=command.effective_on+timedelta(days=1),
        _fields_set={'client_op_id','adjustment_id'})
    with sessions() as db:
        assert reverse(db,db.get(User,'u'),'a','adjust',later)==original
        assert db.query(Transaction).count()==2
