from contextlib import contextmanager
from copy import deepcopy
from datetime import date, datetime
from decimal import Decimal
import importlib.util
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, text, delete

from app.models import (User, Account, Transaction, SyncOperation, UserPreference,
                        ExchangeRate, UserExchangeRate, NetWorthSnapshot, AccountMutationAudit)
from app.backup import service
from app.backup.schemas import RestoreIn
from app.config import get_settings
from test_adjustments import api, account, post, H, D
from test_sync_v2 import op, push


@pytest.fixture(autouse=True)
def isolated_rate_limiter():
    from app.core.rate_limit import auth_limiter
    auth_limiter.clear()
    yield
    auth_limiter.clear()


@pytest.fixture
def target_api(tmp_path):
    directory = tmp_path/'target'
    directory.mkdir()
    with contextmanager(api.__wrapped__)(directory) as target:
        yield target


def empty_backup(**changes):
    return dict(kind='suixiangji.backup', schema_version=3, owner_id='u', source_server_version=0,
                protocol_metadata=dict(min_client_protocol=1), **changes)


def seed_adjustments(client):
    account(client)
    assert post(client).status_code == 200
    reverse = client.post('/assets/accounts/a/calibrations/adjust/reverse', json=dict(
        client_op_id='reverse-op', adjustment_id='reverse', effective_on=D.isoformat()))
    assert reverse.status_code == 200, reverse.text
    body = push(client, op('self', {'default_account_id':'a'}, entity='user_preferences', opid='preference'))
    assert body.status_code == 200 and not body.json()['rejected']


def export(client):
    response = client.get('/backup/export', headers=H)
    assert response.status_code == 200, response.text
    assert response.json()['schema_version'] == 3
    return response.json()


def test_adjustments_preferences_receipts_roundtrip_into_empty_database(api, target_api):
    client, sessions = api
    seed_adjustments(client)
    source = export(client)
    assert len(source['transactions']) == 2
    assert {row['reverses_transaction_id'] for row in source['transactions']} == {None,'adjust'}
    target, target_sessions = target_api
    source['restore_id'] = 'fresh-roundtrip'
    response = target.post('/backup/restore', headers=H, json=source)
    assert response.status_code == 200, response.text
    assert response.json()['transactions'] == 2
    current = export(target)
    assert current['transactions'] == source['transactions']
    assert current['accounts'] == source['accounts']
    assert current['user_preferences'][0]['default_account_id'] == 'a'
    assert current['protocol_metadata']['min_client_protocol'] == 2
    source_receipts = {row['client_op_id']:row for row in source['sync_operations']}
    target_receipts = {row['client_op_id']:row for row in current['sync_operations']}
    assert all(target_receipts[key] == value for key,value in source_receipts.items())
    with target_sessions() as db:
        assert db.query(Transaction).count() == 2
        assert db.get(User,'u').sync_version > source['source_server_version']
        before = db.get(User,'u').sync_version
    replay = target.post('/backup/restore', headers=H, json=source)
    assert replay.status_code == 200 and replay.json()['replayed']
    with target_sessions() as db:
        assert db.get(User,'u').sync_version == before and db.query(Transaction).count() == 2
    # Imported V2 receipts still replay instead of applying the preference again.
    replay = push(target, op('self', {'default_account_id':'a'}, entity='user_preferences', opid='preference')).json()
    assert replay['results'][0] == source_receipts['preference']['result_json']['result']


def test_fx_and_net_worth_roundtrip_are_tenant_scoped(api,target_api):
    client,sessions=api
    with sessions.begin() as db:
        db.add(ExchangeRate(base_currency='USD',quote_currency='CNY',rate=7,rate_date=D,source='cache'))
        db.add(ExchangeRate(base_currency='EUR',quote_currency='CNY',rate=8,rate_date=D,source='unrelated'))
        db.add(UserExchangeRate(user_id='other',base_currency='GBP',quote_currency='CNY',rate=9,rate_date=D,source='private'))
    account(client,currency='USD',opening_rate_date=D.isoformat(),opening_rate_source='cache')
    # Financial writes invalidate old snapshots; seed the backup cache after the write.
    with sessions.begin() as db:
        db.add(NetWorthSnapshot(user_id='u',month='2026-09',total_assets_cny=700,
                               total_liabilities_cny=0,net_worth_cny=700,pending_conversion_count=0))
    source=export(client)
    assert len(source['exchange_rates'])==1 and source['exchange_rates'][0]['base_currency']=='USD'
    assert source['net_worth_snapshots'][0]['net_worth_cny']=='700.000000'
    target,target_sessions=target_api
    with target_sessions.begin() as db:
        db.add(ExchangeRate(base_currency='USD',quote_currency='CNY',rate=99,rate_date=D,source='cache'))
    source['restore_id']='fx-roundtrip'
    response=target.post('/backup/restore',headers=H,json=source)
    assert response.status_code==200,response.text
    with target_sessions() as db:
        assert db.query(ExchangeRate).one().rate==99
        assert db.query(UserExchangeRate).filter_by(user_id='u').one().rate==7
        assert db.query(NetWorthSnapshot).filter_by(user_id='u').one().net_worth_cny==700
    restored=export(target)
    assert restored['exchange_rates']==source['exchange_rates']
    assert restored['net_worth_snapshots']==source['net_worth_snapshots']
    from app.auth.service import delete_user
    from app.auth.schemas import DeleteUserIn
    from app.core.security import hash_password
    with target_sessions.begin() as db:db.get(User,'u').password_hash=hash_password('test-password')
    with target_sessions() as db:
        assert delete_user(db,db.get(User,'u'),DeleteUserIn(current_password='test-password'))=={'deleted':True}
        assert db.query(UserExchangeRate).count()==0 and db.query(ExchangeRate).one().rate==99


def test_v3_pending_snapshots_are_not_revalued_from_current_cache(api):
    client,sessions=api
    with sessions.begin() as db:
        db.add(ExchangeRate(base_currency='USD',quote_currency='CNY',rate=99,rate_date=D,source='new'))
    payload=empty_backup(accounts=[dict(id='pending',name='pending',currency='USD',opening_balance='1',opening_cny_amount=None)],
        transactions=[dict(id='tx',client_op_id='tx-op',kind='expense',currency='USD',amount='1',
                           cny_amount=None,exchange_rate=None,conversion_status='pending',account_id='pending',occurred_on=D.isoformat())])
    response=client.post('/backup/restore',headers=H,json=payload)
    assert response.status_code==200,response.text
    with sessions() as db:
        assert db.get(Account,'pending').opening_cny_amount is None
        row=db.get(Transaction,'tx')
        assert row.cny_amount is None and row.exchange_rate is None and row.conversion_status=='pending'


@pytest.mark.parametrize('version',[None,1,2])
def test_imports_legacy_v1_and_v2_without_changing_their_shape(api,version):
    client,sessions=api
    payload=dict(accounts=[dict(id='legacy',name='legacy',opening_balance='2')],transactions=[])
    if version is not None:payload['schema_version']=version
    if version==2:payload.update(kind='suixiangji.backup',owner_id='u')
    response=client.post('/backup/restore',json=payload)
    assert response.status_code==200,response.text
    with sessions() as db:assert db.get(Account,'legacy').opening_balance==2


@pytest.mark.parametrize('damage',['dangling','wrong_amount','cycle','date','duplicate'])
def test_invalid_reversal_graph_rolls_back_everything(api,damage):
    client,sessions=api;seed_adjustments(client);payload=export(client)
    rows={row['id']:row for row in payload['transactions']}
    if damage=='dangling':rows['reverse']['reverses_transaction_id']='missing'
    elif damage=='wrong_amount':rows['reverse']['amount']=rows['reverse']['original_amount']=rows['reverse']['cny_amount']='-24.000000'
    elif damage=='cycle':rows['adjust']['reverses_transaction_id']='reverse'
    elif damage=='date':rows['reverse']['occurred_on']=rows['reverse']['date']='2026-08-31';rows['reverse']['adjustment_meta']['effective_on']='2026-08-31'
    else:
        extra=deepcopy(rows['reverse']);extra.update(id='second-reversal',client_op_id='second-reversal-op')
        payload['transactions'].append(extra)
    payload['restore_id']='invalid-'+damage
    payload['accounts'].append(dict(id='must-not-exist',name='must-not-exist'))
    with sessions() as db:before=db.get(User,'u').sync_version;receipts=db.query(SyncOperation).count()
    response=client.post('/backup/restore',headers=H,json=payload)
    assert response.status_code==422,response.text
    with sessions() as db:
        assert db.get(User,'u').sync_version==before and db.query(SyncOperation).count()==receipts
        assert db.get(Account,'must-not-exist') is None and db.query(Transaction).count()==2


def test_existing_adjustments_cannot_be_overwritten_by_any_backup(api):
    client,sessions=api;seed_adjustments(client);payload=export(client)
    first=next(row for row in payload['transactions'] if row['id']=='adjust')
    original_note=first['note']
    first['note']='tampered';payload['restore_id']='immutable'
    assert client.post('/backup/restore',headers=H,json=payload).status_code==409
    for version in [1,2]:
        legacy=dict(schema_version=version,accounts=[dict(id='a',name='a',opening_balance=999)],transactions=[])
        if version==2:legacy.update(kind='suixiangji.backup',owner_id='u')
        assert client.post('/backup/restore',headers=H,json=legacy).status_code==409
    with sessions() as db:
        assert db.get(Account,'a').opening_balance==100
        assert db.get(Transaction,'adjust').note==original_note


@pytest.mark.parametrize('section',['accounts','transactions','user_preferences','sync_operations','audit','owner'])
def test_foreign_resources_never_cross_the_backup_boundary(api,section):
    client,sessions=api
    with sessions.begin() as db:
        db.add(Account(id='foreign',user_id='other',name='foreign',opening_balance=999,server_version=1))
    payload=empty_backup(accounts=[dict(id='mine',name='mine')])
    if section=='accounts':payload['accounts'].append(dict(id='foreign',name='intruder'))
    elif section=='transactions':payload['transactions']=[dict(id='tx',client_op_id='tx',kind='expense',amount=1,account_id='foreign',occurred_on=D.isoformat())]
    elif section=='user_preferences':payload['user_preferences']=[dict(id='self',default_account_id='foreign')]
    elif section=='sync_operations':payload['sync_operations']=[dict(client_op_id='foreign-receipt',entity='accounts',entity_id='foreign',server_version=0,created_at='2026-09-01T00:00:00')]
    elif section=='audit':payload['account_mutation_audits']=[dict(account_id='foreign',client_op_id='audit',event_kind='repair',before_json={},after_json={},reason='test',created_at='2026-09-01T00:00:00Z')]
    else:payload['owner_id']='other'
    response=client.post('/backup/restore',headers=H,json=payload)
    assert response.status_code in {404,422},response.text
    with sessions() as db:
        assert db.get(Account,'mine') is None and db.get(Account,'foreign').opening_balance==999
        assert db.get(User,'u').sync_version==0 and db.query(SyncOperation).count()==0
    assert 'foreign' not in str(export(client)['accounts'])


def test_mid_restore_failure_rolls_back_entities_preferences_floor_receipts_and_auxiliary(api,target_api,monkeypatch):
    from app.backup import v3_restore
    client,_=api;seed_adjustments(client);payload=export(client);payload['restore_id']='fail-midway'
    payload['protocol_metadata']['min_client_protocol']=2
    target,sessions=target_api
    original=v3_restore._auxiliary
    def fail(*args):
        original(*args)
        raise RuntimeError('Injected after entity, preference and receipt flush')
    monkeypatch.setattr(v3_restore,'_auxiliary',fail)
    with pytest.raises(RuntimeError):target.post('/backup/restore',headers=H,json=payload)
    with sessions() as db:
        for model in [Account,Transaction,SyncOperation,UserPreference,UserExchangeRate,NetWorthSnapshot,AccountMutationAudit]:
            assert db.query(model).count()==0
        assert db.get(User,'u').sync_version==0 and db.get(User,'u').min_client_protocol==1


def test_conflict_results_include_all_ops_and_old_receipts_are_normalized(api):
    client,sessions=api;account(client)
    operation=op('a',{'note':'stale'},opid='old-conflict',base_version=0)
    body=push(client,operation,op('bad',{'name':'bad','kind':'bad'}),op('good',{'name':'good'})).json()
    assert [row['status'] for row in body['results']]==['conflict','rejected','applied']
    assert body['results'][0]['row']==body['conflicts'][0]['authoritative_row']
    with sessions.begin() as db:
        receipt=db.query(SyncOperation).filter_by(client_op_id='old-conflict').one()
        assert receipt.result_json['result']['status']=='conflict'
        receipt.result_json={'conflict':receipt.result_json['conflict']}
    replay=push(client,operation).json()
    assert replay['results'][0]==body['results'][0] and replay['conflicts']==body['conflicts']


def test_export_advances_one_version_and_floor_gate_writes_nothing(api):
    client,sessions=api
    assert export(client)['source_server_version']==1
    assert export(client)['source_server_version']==2
    with sessions.begin() as db:db.get(User,'u').min_client_protocol=2
    response=client.get('/backup/export')
    assert response.status_code==426 and response.json()==dict(code='upgrade_required',min_protocol=2)
    with sessions() as db:
        assert db.get(User,'u').sync_version==2 and db.query(SyncOperation).count()==2


@pytest.mark.parametrize('version',[1,2,3])
@pytest.mark.parametrize('amount',['NaN','1e1000000','0.0000001'])
def test_invalid_financial_values_are_422_and_do_not_write(api,version,amount):
    client,sessions=api
    payload=dict(schema_version=version,accounts=[dict(id='bad',name='bad',opening_balance=amount)],transactions=[])
    if version>=2:payload.update(kind='suixiangji.backup',owner_id='u')
    if version==3:payload.update(protocol_metadata=dict(min_client_protocol=1),source_server_version=0)
    response=client.post('/backup/restore',headers=H,json=payload)
    assert response.status_code==422,response.text
    with sessions() as db:
        assert db.query(Account).count()==0 and db.get(User,'u').sync_version==0


def test_imported_receipts_cannot_replace_an_existing_outcome(api):
    client,sessions=api
    push(client,op('a',{'name':'a'}))
    payload=export(client);payload['restore_id']='changed-receipt'
    receipt=next(row for row in payload['sync_operations'] if row['client_op_id']=='a-op')
    receipt['request_hash']='f'*64
    payload['accounts'].append(dict(id='rollback',name='rollback'))
    before=payload['source_server_version']
    response=client.post('/backup/restore',headers=H,json=payload)
    assert response.status_code==409,response.text
    with sessions() as db:
        assert db.get(Account,'rollback') is None and db.get(User,'u').sync_version==before


def test_restore_hash_includes_protocol_receipts_preferences_fx_and_snapshots(api):
    client,_=api
    payload=empty_backup(restore_id='hash-guard')
    assert client.post('/backup/restore',headers=H,json=payload).status_code==200
    for field,value in [('protocol_metadata',dict(min_client_protocol=2)),
                        ('user_preferences',[dict(default_account_id=None)]),
                        ('exchange_rates',[dict(base_currency='USD',quote_currency='CNY',rate='7',rate_date='2026-09-01',source='test',fetched_at='2026-09-01T00:00:00')]),
                        ('net_worth_snapshots',[dict(month='2026-09',total_assets_cny=0,total_liabilities_cny=0,net_worth_cny=0,pending_conversion_count=0,created_at='2026-09-01T00:00:00')])]:
        changed=deepcopy(payload);changed[field]=value
        response=client.post('/backup/restore',headers=H,json=changed)
        assert response.status_code==409 and response.json()['detail']['code']=='operation_mismatch'


def test_restoring_audit_records_is_idempotent_and_lossless(api,target_api):
    client,_=api
    push(client,op('a',{'name':'same'}),op('b',{'name':'same'}))
    payload=export(client);payload['restore_id']='audits'
    assert len(payload['account_mutation_audits'])==1
    target,sessions=target_api
    assert target.post('/backup/restore',headers=H,json=payload).status_code==200
    assert export(target)['account_mutation_audits']==payload['account_mutation_audits']
    assert target.post('/backup/restore',headers=H,json=payload).json()['replayed']
    with sessions() as db:assert db.query(AccountMutationAudit).count()==1


def test_rejected_foreign_id_receipts_roundtrip_without_foreign_data(api,target_api):
    client,sessions=api;target,target_sessions=target_api
    for store in (sessions,target_sessions):
        with store.begin() as db:
            db.add(Account(id='foreign',user_id='other',name='private-name',opening_balance=999,server_version=1))
    operation=op('foreign',{'name':'attempt'},opid='rejected-foreign')
    assert push(client,operation).json()['rejected'][0]['code']=='not_found'
    payload=export(client);payload['restore_id']='rejected-receipt'
    assert payload['accounts']==[] and 'private-name' not in str(payload)
    response=target.post('/backup/restore',headers=H,json=payload)
    assert response.status_code==200,response.text
    assert push(target,operation).json()['rejected'][0]['code']=='not_found'
    with target_sessions() as db:assert db.get(Account,'foreign').name=='private-name'


def test_0008_migration_replay_preserves_existing_protocol_and_user_fx(tmp_path,monkeypatch):
    url=f"sqlite:///{tmp_path/'migration.db'}"
    monkeypatch.setenv('WEALTHMATE_DATABASE_URL',url);get_settings.cache_clear()
    backend=Path(__file__).resolve().parents[1];config=Config(str(backend/'alembic.ini'))
    command.upgrade(config,'0007_v110_sync_v2')
    engine=create_engine(url)
    with engine.begin() as db:
        db.execute(text("INSERT INTO users(id,username,password_hash,display_name,quick_memories,auth_version,sync_version,min_client_protocol) VALUES ('u','u','x','u','[]',0,42,2)"))
    command.upgrade(config,'head')
    spec=importlib.util.spec_from_file_location('backup_migration',backend/'migrations/versions/0008_v110_backup_v3.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    with engine.begin() as db:
        db.execute(text("INSERT INTO user_exchange_rates(user_id,base_currency,quote_currency,rate,rate_date,source) VALUES ('u','USD','CNY',7,'2026-09-01','test')"))
        for _ in range(2):
            with Operations.context(MigrationContext.configure(db)):module.upgrade()
        assert db.execute(text('SELECT sync_version,min_client_protocol FROM users')).one()==(42,2)
        assert db.execute(text('SELECT count(*) FROM user_exchange_rates')).scalar()==1
    engine.dispose();get_settings.cache_clear()
