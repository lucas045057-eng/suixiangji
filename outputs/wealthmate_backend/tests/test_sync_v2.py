from datetime import datetime
from pathlib import Path
import importlib.util
import io
import json
import pytest
from fastapi import HTTPException
from sqlalchemy import select, delete, event, create_engine, text
from sqlalchemy.orm import Session
from alembic import command
from alembic.config import Config
from alembic.operations import Operations
from alembic.migration import MigrationContext
from app.models import Account, AccountMutationAudit, Category, Transaction, SyncOperation, User, UserPreference
from app.config import get_settings
from app.assets.schemas import AccountIn
from app.assets.service import create_account
from app.sync.schemas import SyncPushIn, SyncPushV2In
from app.sync import service, v2
from test_adjustments import api
from test_sync_postgres_concurrency import postgres_case

H={"X-Wealthmate-Sync-Protocol":"2"}

@pytest.fixture(autouse=True)
def settings(monkeypatch):
    monkeypatch.setenv("WEALTHMATE_MIN_CLIENT_PROTOCOL","1")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()

def op(identifier,payload=None,entity='accounts',opid=None,**extra):
    return dict(client_op_id=opid or identifier+'-op',entity=entity,entity_id=identifier,type='upsert',payload=payload or {},**extra)

def push(client,*operations,headers=H):
    return client.post('/sync/push',headers=headers,json={'operations':list(operations)})

def account(client,identifier='a',**values):
    result=client.post('/accounts',json=dict(id=identifier,name=identifier,opening_balance=100,**values))
    assert result.status_code==200,result.text
    return result.json()

def test_v1_shape_and_business_atomicity_remain(api):
    client,sessions=api
    result=push(client,op('a',{'name':'a'}),headers={})
    assert result.status_code==200 and set(result.json())=={'accepted','conflicts','server_version'}
    result=push(client,op('b',{'name':'b'}),op('bad',{'name':'bad','kind':'weird'}),headers={})
    assert result.status_code==422
    with sessions() as db:assert db.get(Account,'b') is None
    body=client.get('/sync/pull').json()
    assert 'preferences' not in body and 'results' not in body

@pytest.mark.parametrize('bad',[{'kind':'weird'},{'currency':'EU'},{'note':'x'*257},{'archived_at':123},{'opening_balance':'NaN'}])
def test_rejection_isolated_and_idempotent(api,bad):
    client,sessions=api
    operations=[op('bad',{'name':'bad',**bad}),op('valid',{'name':'valid'})]
    response=push(client,*operations)
    assert response.status_code==200,response.text
    body=response.json();assert set(body)=={'server_version','results','rejected','conflicts'}
    assert [r['status'] for r in body['results']]==['rejected','applied']
    assert [r['op_id'] for r in body['rejected']]==['bad-op'] and body['conflicts']==[]
    assert body['server_version']==1
    with sessions() as db:
        assert db.get(Account,'bad') is None and db.get(Account,'valid') is not None
        assert db.query(SyncOperation).count()==2
    assert push(client,*operations).json()==body


def test_name_collision_suffix_is_accepted_and_audited(api):
    client,sessions=api
    response=push(client,op('first',{'name':'Card','opening_balance':11}),op('second',{'name':'ＣＡＲＤ','opening_balance':22}))
    body=response.json();assert body['rejected']==body['conflicts']==[]
    assert all(r['status']=='applied' for r in body['results'])
    second=body['results'][1]['row'];assert second['id']=='second' and second['opening_balance']==22
    assert second['name'].endswith('·second')
    with sessions() as db:assert db.query(AccountMutationAudit).one().event_kind=='v2_name_repaired'
    assert push(client,op('second',{'name':'ＣＡＲＤ','opening_balance':22})).json()['results'][0]['row']==second


def test_different_field_merge_and_field_conflict_apply_other_fields(api):
    client,sessions=api;initial=account(client)
    assert client.patch('/accounts/a',json={'name':'server-name'}).status_code==200
    first=push(client,op('a',{'note':'client-note'},opid='merge-note',base_version=initial['server_version'],base={'note':''})).json()
    assert first['results'][0]['status']=='merged'
    assert first['results'][0]['row']['name']=='server-name'
    assert first['results'][0]['row']['note']=='client-note'
    second=push(client,op('a',{'note':'competing','archived_at':'2026-09-01T00:00:00'},opid='merge-conflict',base={'note':'','archived_at':None})).json()
    result=second['results'][0]
    assert result['status']=='merged' and result['field_conflicts'][0]['field']=='note'
    assert result['fields_applied']==['archived_at']
    assert result['row']['note']=='client-note' and result['row']['archived_at'] is not None
    assert second['rejected']==second['conflicts']==[]


def test_financial_conflict_rejects_whole_operation_only(api):
    client,sessions=api;account(client)
    client.patch('/accounts/a',json={'opening_balance':125})
    body=push(client,op('a',{'opening_balance':150,'name':'unwanted'},opid='financial',base={'opening_balance':100,'name':'a'}),op('other',{'name':'other'})).json()
    assert body['rejected'][0]['code']=='financial_conflict' and body['rejected'][0]['field']=='opening_balance'
    assert body['conflicts']==[]
    with sessions() as db:
        a=db.get(Account,'a');assert a.name=='a' and a.opening_balance==125
        assert db.get(Account,'other') is not None


def test_version_competition_only_enters_conflicts_and_replays(api):
    client,sessions=api;a=account(client)
    client.patch('/accounts/a',json={'note':'new'})
    operation=op('a',{'note':'old'},opid='version-race',base_version=a['server_version'])
    body=push(client,operation,op('valid',{'name':'valid'})).json()
    assert body['rejected']==[] and len(body['conflicts'])==1
    assert body['conflicts'][0]['reason']=='version_conflict'
    assert body['conflicts'][0]['authoritative_row']['note']=='new'
    assert [r['id'] for r in body['results']]==['valid']
    assert push(client,operation).json()['conflicts']==body['conflicts']

@pytest.mark.parametrize('route',['/sync/push','/sync/pull'])
def test_floor_gate_zero_writes_and_v2_passes(api,route):
    client,sessions=api
    with sessions.begin() as db:db.get(User,'u').min_client_protocol=2
    before=0
    response=client.post(route,json={'operations':[op('denied',{'name':'denied'})]}) if route.endswith('push') else client.get(route)
    assert response.status_code==426 and response.json()=={'code':'upgrade_required','min_protocol':2}
    with sessions() as db:
        assert db.get(User,'u').sync_version==before and db.query(SyncOperation).count()==0
    response=push(client,op('ok',{'name':'ok'})) if route.endswith('push') else client.get(route,headers=H)
    assert response.status_code==200


def test_environment_can_raise_protocol_floor(api,monkeypatch):
    client,sessions=api
    monkeypatch.setenv('WEALTHMATE_MIN_CLIENT_PROTOCOL','2');get_settings.cache_clear()
    assert client.get('/sync/pull').json()=={'code':'upgrade_required','min_protocol':2}
    assert client.get('/sync/pull',headers=H).status_code==200
    with sessions() as db:assert db.query(SyncOperation).count()==0


def test_preferences_pull_projection_and_archiving_default(api):
    client,sessions=api;account(client,'a');account(client,'b')
    cursor=client.get('/sync/pull').json()['server_version']
    result=push(client,op('self',{'default_account_id':'a'},entity='user_preferences')).json()
    assert result['rejected']==result['conflicts']==[]
    row=result['results'][0]['row'];assert row['id']=='self' and row['default_account_id']=='a'
    pulled=client.get('/sync/pull?since_version='+str(cursor),headers=H).json()
    assert pulled['preferences']==[row]
    assert next(a for a in pulled['accounts'] if a['id']=='a')['is_default_payment'] is True
    assert 'preferences' not in client.get('/sync/pull').json()
    assert client.get('/sync/pull?since_version='+str(result['server_version']),headers=H).json()['preferences']==[]
    new=push(client,op('self',{'default_account_id':'b'},entity='user_preferences',opid='change-default',base_version=row['server_version'])).json()
    with sessions() as db:
        assert not db.get(Account,'a').is_default_payment and db.get(Account,'b').is_default_payment
        assert db.get(UserPreference,'u').default_account_id=='b'
    archive=push(client,op('b',{'archived_at':'2026-09-01T00:00:00'},opid='archive')).json()
    assert archive['rejected']==[]
    with sessions() as db:
        assert db.get(UserPreference,'u').default_account_id is None
        assert not db.get(Account,'b').is_default_payment
        assert db.query(UserPreference).count()==1


def test_preferences_reject_cross_user_and_readonly_projection(api):
    client,sessions=api;account(client)
    with sessions.begin() as db:db.get(Account,'a').user_id='other'
    result=push(client,op('self',{'default_account_id':'a'},entity='user_preferences')).json()
    assert result['rejected'][0]['code']=='invalid_default_account'
    result=push(client,op('foreign-id',{},entity='user_preferences')).json()
    assert result['rejected'][0]['code']=='invalid_preference_id'
    result=push(client,op('new',{'name':'new','is_default_payment':True})).json()
    assert result['rejected'][0]['code']=='read_only_field'


def test_invalid_dependency_and_foreign_entity_do_not_roll_back_other_ops(api):
    client,sessions=api;account(client,'foreign')
    with sessions.begin() as db:db.get(Account,'foreign').user_id='other'
    transaction=op('tx',dict(kind='expense',amount=1,account_id='bad',occurred_on='2026-09-01'),entity='transactions')
    response=push(client,transaction,op('bad',{'name':'bad','kind':'weird'}),op('foreign',{'name':'attack'}),op('good',{'name':'good'}))
    assert response.status_code==200
    codes={r['id']:r['code'] for r in response.json()['rejected']}
    assert codes=={'bad':'invalid_field','tx':'dependency_rejected','foreign':'not_found'}
    with sessions() as db:
        assert db.get(Account,'foreign').name=='foreign'
        assert db.get(Account,'good') is not None and db.get(Transaction,'tx') is None


def test_transaction_validation_isolated_and_legacy_round_trip(api):
    client,sessions=api;account(client)
    first=op('tx',dict(type='expense',amount='1.123456',account_id='a',date='2026-09-01',deleted_at=None,conversion_status='ready'),entity='transactions')
    bad=op('bad-tx',dict(kind='weird',amount=1,account_id='a',occurred_on='2026-09-01'),entity='transactions')
    body=push(client,first,bad).json()
    assert body['results'][0]['status']=='applied' and body['rejected'][0]['id']=='bad-tx'
    assert push(client,first).json()['results']==body['results'][:1]
    invalid=op('invalid-ref',dict(kind='expense',amount=1,account_id={},occurred_on='2026-09-01'),entity='transactions')
    assert push(client,invalid).json()['rejected'][0]['field']=='account_id'


def test_unknown_failure_rolls_back_prior_savepoints_and_receipts(api,monkeypatch):
    client,sessions=api
    original=v2._apply
    def fail(db,user,operation,existing):
        if operation.entity_id=='later':raise RuntimeError('injected unknown failure')
        return original(db,user,operation,existing)
    monkeypatch.setattr(v2,'_apply',fail)
    with pytest.raises(RuntimeError,match='injected unknown failure'):
        push(client,op('first',{'name':'first'}),op('later',{'name':'later'}))
    with sessions() as db:
        assert db.query(Account).count()==db.query(SyncOperation).count()==0
        assert db.get(User,'u').sync_version==0


def test_operation_mismatch_and_duplicate_envelope(api):
    client,sessions=api
    first=op('a',{'name':'a'})
    assert push(client,first).json()['results'][0]['status']=='applied'
    changed=op('a',{'name':'changed'})
    assert push(client,changed).json()['rejected'][0]['code']=='operation_mismatch'
    assert push(client,first,first).status_code==422


def test_floor_rechecked_after_postgres_lock_wait(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event
    from app.db import SessionLocal
    engine,prefix,user_id=postgres_case
    stale=SessionLocal(bind=engine);old_user=stale.get(User,user_id);waiting=Event()
    def reached(_conn,_cursor,statement,_parameters,_context,_many):
        if 'FOR UPDATE' in statement:waiting.set()
    event.listen(engine,'before_cursor_execute',reached)
    try:
        with SessionLocal(bind=engine) as admin,ThreadPoolExecutor(max_workers=1) as pool:
            current=admin.query(User).filter(User.id==user_id).with_for_update().one()
            waiting.clear()
            future=pool.submit(service.push,SyncPushIn(operations=[op(prefix,{'name':prefix})]),stale,old_user)
            assert waiting.wait(timeout=10)
            current.min_client_protocol=2;admin.commit()
            with pytest.raises(HTTPException) as exc:future.result(timeout=15)
            assert exc.value.status_code==426 and exc.value.detail['min_protocol']==2
    finally:
        event.remove(engine,'before_cursor_execute',reached);stale.close()
    with SessionLocal(bind=engine) as db:
        assert db.get(Account,prefix) is None
        assert db.query(SyncOperation).filter_by(user_id=user_id).count()==0
        assert db.get(User,user_id).sync_version==0


def test_postgres_different_field_updates_merge_under_lock(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from app.db import SessionLocal
    engine,prefix,user_id=postgres_case;identifier=prefix+'a'
    with SessionLocal(bind=engine) as db:
        create_account(db,db.get(User,user_id),AccountIn(id=identifier,name=identifier))
    start=Barrier(2)
    def update(field,value):
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            operation=op(identifier,{field:value},opid=prefix+field,base_version=1,base={'name':identifier,'note':''})
            start.wait(timeout=10)
            return v2.push(SyncPushV2In(operations=[operation]),db,user)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            a=pool.submit(update,'name',prefix+'renamed');b=pool.submit(update,'note','new-note')
            results=[a.result(timeout=15),b.result(timeout=15)]
        assert all(r['results'][0]['status']=='merged' and not r['conflicts'] and not r['rejected'] for r in results)
        with SessionLocal(bind=engine) as db:
            row=db.get(Account,identifier)
            assert row.name==prefix+'renamed' and row.note=='new-note'
            assert db.get(User,user_id).sync_version==3
    finally:
        with SessionLocal(bind=engine) as db:
            db.execute(delete(Account).where(Account.user_id==user_id));db.commit()


def test_0007_migration_is_idempotent_preserves_cursor_and_legacy_receipts(tmp_path,monkeypatch):
    url=f"sqlite:///{tmp_path/'v2.db'}";monkeypatch.setenv('WEALTHMATE_DATABASE_URL',url);get_settings.cache_clear()
    root=Path(__file__).resolve().parents[1];cfg=Config(str(root/'alembic.ini'))
    command.upgrade(cfg,'0006_v110_adjustments');engine=create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users(id,username,password_hash,display_name,quick_memories,auth_version,sync_version) VALUES ('legacy','legacy','x','legacy','[]',0,42)"))
        db.execute(text("INSERT INTO sync_operations(user_id,client_op_id,entity,entity_id,server_version) VALUES ('legacy','old-op','accounts','a',42)"))
    command.upgrade(cfg,'head')
    spec=importlib.util.spec_from_file_location('sync_v2_migration',root/'migrations/versions/0007_v110_sync_v2.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with engine.begin() as db:
        with Operations.context(MigrationContext.configure(db)):module.upgrade()
        assert db.execute(text('SELECT sync_version,min_client_protocol FROM users')).one()==(42,1)
        assert db.execute(text('SELECT server_version,protocol_version,request_hash,result_json FROM sync_operations')).one()==(42,1,None,None)
    engine.dispose();get_settings.cache_clear()


@pytest.mark.parametrize('extra',[{'base_version':True},{'base_version':-1},{'base_version':'1'}, {'base':[]}])
def test_invalid_baselines_rejected_per_operation(api,extra):
    client,_=api
    body=push(client,op('bad',{'name':'bad'},**extra),op('good',{'name':'good'})).json()
    assert body['results'][0]['status']=='rejected' and body['results'][1]['status']=='applied'
    assert body['conflicts']==[]


def test_invalid_derived_field_and_nonfinite_json_do_not_poison_batch(api):
    client,_=api;account(client)
    invalid=op('tx',dict(kind='expense',amount=1,account_id='a',occurred_on='2026-09-01',conversion_status=[]),entity='transactions')
    assert push(client,invalid,op('valid',{'name':'valid'})).json()['results'][1]['status']=='applied'
    operations=[op('nan',{'name':'nan','opening_balance':float('nan')}),op('valid2',{'name':'valid2'})]
    response=client.post('/sync/push',headers={**H,'Content-Type':'application/json'},content=json.dumps({'operations':operations}))
    assert response.status_code==200,response.text
    assert response.json()['results'][0]['status']=='rejected' and response.json()['results'][1]['status']=='applied'


def test_financial_group_change_does_not_merge_opening_into_new_currency(api):
    client,sessions=api;account(client)
    client.patch('/accounts/a',json={'currency':'USD'})
    body=push(client,op('a',{'opening_balance':200},opid='financial-group',base={'opening_balance':100,'currency':'CNY'})).json()
    assert body['rejected'][0]['code']=='financial_conflict' and body['rejected'][0]['field']=='currency'
    with sessions() as db:assert db.get(Account,'a').opening_balance==100


def test_new_preference_and_audit_do_not_block_account_deletion(api):
    from app.auth.service import delete_user
    from app.auth.schemas import DeleteUserIn
    from app.core.security import hash_password
    client,sessions=api
    push(client,op('a',{'name':'same'}),op('b',{'name':'same'}))
    push(client,op('self',{'default_account_id':'a'},entity='user_preferences'))
    with sessions.begin() as db:db.get(User,'u').password_hash=hash_password('test-password')
    with sessions() as db:
        assert delete_user(db,db.get(User,'u'),DeleteUserIn(current_password='test-password'))=={'deleted':True}
        assert db.get(UserPreference,'u') is None and db.query(AccountMutationAudit).count()==0


def test_balance_changed_is_conflict_not_business_rejection(api,monkeypatch):
    client,sessions=api;account(client)
    original=v2._apply
    def compete(db,user,operation,existing):
        if operation.entity_id=='a':raise HTTPException(409,detail={'code':'balance_changed','message':'Changed'})
        return original(db,user,operation,existing)
    monkeypatch.setattr(v2,'_apply',compete)
    body=push(client,op('a',{'note':'note'},opid='balance'),op('b',{'name':'b'})).json()
    assert body['conflicts'][0]['reason']=='balance_changed' and body['rejected']==[]
    assert body['results'][0]['id']=='b'


@pytest.mark.parametrize('payload',[
    {'name':'nul\x00name'}, {'name':'long-source','opening_rate_source':'s'*257},
])
def test_database_text_validation_rejects_only_bad_operation(api,payload):
    client,_=api
    body=push(client,op('bad',payload),op('good',{'name':'good'})).json()
    assert body['results'][0]['status']=='rejected' and body['results'][1]['status']=='applied'
    assert body['rejected'][0]['code']=='invalid_field'


def test_invalid_envelope_identifier_is_422_without_receipt(api):
    client,sessions=api
    assert push(client,op('bad\x00id',{'name':'bad'})).status_code==422
    with sessions() as db:assert db.query(SyncOperation).count()==0



def test_v1_does_not_misread_rejected_v2_receipt_as_accepted(api):
    client,sessions=api
    rejected=op('bad',{'name':'bad','kind':'invalid'},opid='cross-protocol')
    assert push(client,rejected).json()['rejected']
    response=push(client,op('good',{'name':'good'}),op('bad',{'name':'bad'},opid='cross-protocol'),headers={})
    assert response.status_code==409
    with sessions() as db:
        assert db.query(Account).count()==0 and db.query(SyncOperation).count()==1
        assert db.get(User,'u').sync_version==0



def test_derived_opening_overflow_is_rejected_without_poisoning_batch(api):
    from datetime import date
    from app.models import ExchangeRate
    client,sessions=api
    with sessions.begin() as db:
        db.add(ExchangeRate(base_currency='USD',quote_currency='CNY',rate=100,
                           rate_date=date(2026,9,1),source='test'))
    body=push(client,op('overflow',{'name':'overflow','currency':'USD','opening_balance':'99999999999999'}),
              op('good',{'name':'good'})).json()
    assert body['rejected'][0]['code']=='invalid_amount'
    assert body['results'][1]['status']=='applied'
    with sessions() as db:
        assert db.get(Account,'overflow') is None and db.get(Account,'good').server_version==1
        assert db.get(User,'u').sync_version==1
