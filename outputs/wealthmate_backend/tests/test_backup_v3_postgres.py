from concurrent.futures import ThreadPoolExecutor
from datetime import date
from decimal import Decimal
from threading import Barrier, Event

from sqlalchemy import delete, event

from app.db import SessionLocal
from app.models import (Account, User, UserPreference, UserExchangeRate, AccountMutationAudit,
                        Transaction, SyncOperation, NetWorthSnapshot)
from app.backup.schemas import RestoreIn
from app.backup.service import export_backup, restore_backup
from app.sync.service import pull, push
from app.sync.schemas import SyncPushIn
from test_sync_postgres_concurrency import postgres_case


def cleanup(engine,user_id):
    with SessionLocal(bind=engine) as db:
        for model in (UserPreference,UserExchangeRate,AccountMutationAudit,Transaction,NetWorthSnapshot,Account):
            db.execute(delete(model).where(model.user_id==user_id))
        db.commit()


def test_postgres_v3_concurrent_exports_have_distinct_consistent_cuts(postgres_case):
    engine,prefix,user_id=postgres_case
    start=Barrier(2)
    def export():
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            start.wait(timeout=10)
            return export_backup(db,user,protocol=2)
    with ThreadPoolExecutor(max_workers=2) as pool:
        first=pool.submit(export);second=pool.submit(export)
        results=[first.result(timeout=20),second.result(timeout=20)]
    assert sorted(row['source_server_version'] for row in results)==[1,2]
    for row in results:
        assert row['schema_version']==3
        assert len(row['sync_operations'])==row['source_server_version']
        assert all(receipt['server_version']<=row['source_server_version'] for receipt in row['sync_operations'])


def test_postgres_v3_duplicate_restores_write_entities_and_receipt_once(postgres_case):
    engine,prefix,user_id=postgres_case
    payload=RestoreIn(kind='suixiangji.backup',schema_version=3,owner_id=user_id,
        source_server_version=0,protocol_metadata={'min_client_protocol':1},restore_id=prefix,
        accounts=[dict(id=prefix,name=prefix,opening_balance='1.123456')])
    start=Barrier(2)
    def restore():
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            start.wait(timeout=10)
            return restore_backup(payload,db,user,protocol=2)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            first=pool.submit(restore);second=pool.submit(restore)
            results=[first.result(timeout=20),second.result(timeout=20)]
        assert sorted(row['replayed'] for row in results)==[False,True]
        assert {row['server_version'] for row in results}=={2}
        with SessionLocal(bind=engine) as db:
            assert db.get(User,user_id).sync_version==2
            assert str(db.get(Account,prefix).opening_balance)=='1.123456'
    finally:
        cleanup(engine,user_id)


def test_postgres_shared_pulls_coexist_and_exclude_writes(postgres_case):
    engine,prefix,user_id=postgres_case
    readers=[SessionLocal(bind=engine),SessionLocal(bind=engine)]
    pool=ThreadPoolExecutor(max_workers=2)
    writer_waiting=Event()
    statements=[]
    def observed(_connection,_cursor,statement,_parameters,_context,_many):
        if 'FOR SHARE' in statement:statements.append(statement)
        if 'FOR UPDATE' in statement:writer_waiting.set()
    event.listen(engine,'before_cursor_execute',observed)
    future=None
    try:
        first=pull(0,readers[0],readers[0].get(User,user_id))
        def read():return pull(0,readers[1],readers[1].get(User,user_id))
        # A FOR UPDATE implementation would block this second independent reader.
        assert pool.submit(read).result(timeout=5)==first
        assert len(statements)==2
        def write():
            with SessionLocal(bind=engine) as db:
                return push(SyncPushIn(operations=[dict(client_op_id=prefix,entity='accounts',entity_id=prefix,
                    type='upsert',payload={'name':prefix})]),db,db.get(User,user_id))
        future=pool.submit(write)
        assert writer_waiting.wait(timeout=5) and not future.done()
        for db in readers:db.rollback()
        assert future.result(timeout=10)['server_version']==1
    finally:
        for db in readers:db.close()
        pool.shutdown(wait=True)
        event.remove(engine,'before_cursor_execute',observed)
        cleanup(engine,user_id)


def test_postgres_v3_adjustment_full_restore_roundtrip(postgres_case):
    from app.assets.service import create_account
    from app.assets.schemas import AccountIn, CalibrationIn, ReverseCalibrationIn
    from app.assets.calibration import calibrate, reverse
    from app.sync.v2 import push as push_v2
    from app.sync.schemas import SyncPushV2In
    engine,prefix,user_id=postgres_case
    day=date(2026,9,1)
    try:
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            create_account(db,user,AccountIn(id=prefix,name=prefix,opening_balance=100))
            calibrate(db,user,prefix,CalibrationIn(client_op_id=prefix+'-calibrate',adjustment_id=prefix+'-adj',
                target_cny='125.00',expected_current_cny='100.000000',effective_on=day))
            reverse(db,user,prefix,prefix+'-adj',ReverseCalibrationIn(client_op_id=prefix+'-reverse',
                adjustment_id=prefix+'-rev',effective_on=day))
            push_v2(SyncPushV2In(operations=[dict(client_op_id=prefix+'-pref',entity='user_preferences',
                entity_id='self',type='upsert',payload={'default_account_id':prefix})]),db,user)
            db.add(UserExchangeRate(user_id=user_id,base_currency='USD',quote_currency='CNY',rate=7,
                                   rate_date=day,source='restored'))
            db.add(AccountMutationAudit(user_id=user_id,account_id=prefix,client_op_id=prefix+'-audit',
                event_kind='test_backup',before_json={},after_json={'name':prefix},reason='test'))
            db.add(NetWorthSnapshot(user_id=user_id,month='2026-09',total_assets_cny=100,
                total_liabilities_cny=0,net_worth_cny=100,pending_conversion_count=0))
            db.commit()
            source=export_backup(db,user,protocol=2)
        # Empty this owner's data only. Other test users and public rates remain untouched.
        cleanup(engine,user_id)
        with SessionLocal(bind=engine) as db:
            db.execute(delete(SyncOperation).where(SyncOperation.user_id==user_id));db.commit()
            payload=RestoreIn(**source,restore_id=prefix+'-restore')
            result=restore_backup(payload,db,db.get(User,user_id),protocol=2)
            assert not result['replayed'] and result['transactions']==2
            current=export_backup(db,db.get(User,user_id),protocol=2)
            for section in ('accounts','categories','transactions','budgets','exchange_rates',
                            'net_worth_snapshots','account_mutation_audits'):
                assert current[section]==source[section],section
            assert current['user_preferences'][0]['default_account_id']==prefix
            assert current['protocol_metadata']['min_client_protocol']==2
            receipts={row['client_op_id']:row for row in current['sync_operations']}
            assert all(receipts[row['client_op_id']]==row for row in source['sync_operations'])
            assert db.get(Transaction,prefix+'-adj').amount==Decimal('25')
            assert db.get(Transaction,prefix+'-rev').reverses_transaction_id==prefix+'-adj'
            before=db.get(User,user_id).sync_version
            replay=restore_backup(payload,db,db.get(User,user_id),protocol=2)
            assert replay['replayed'] and db.get(User,user_id).sync_version==before
    finally:
        cleanup(engine,user_id)
