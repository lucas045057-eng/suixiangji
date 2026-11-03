from concurrent.futures import ThreadPoolExecutor
from datetime import date
from threading import Barrier

from fastapi import HTTPException

from app.assets.basis import issue
from app.assets.calibration import calibrate
from app.assets.schemas import AccountIn, CalibrationIn
from app.assets.service import create_account, wealth_snapshot
from app.db import SessionLocal
from app.insights.service import _save_net_worth_snapshot
from app.ledger.schemas import TransactionIn
from app.ledger.service import create_transaction
from app.models import Account, Transaction, User, NetWorthSnapshot
from test_backup_v3_postgres import cleanup
from test_sync_postgres_concurrency import postgres_case


def test_postgres_same_basis_allows_only_one_calibration(postgres_case):
    engine,prefix,user_id=postgres_case
    try:
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            create_account(db,user,AccountIn(id=prefix,name=prefix,opening_balance=100))
            token=issue(db,user,prefix,date(2026,9,1),protocol=2)['basis_token']
            db.rollback()  # Release the GET's shared lock before the two writers.
        start=Barrier(2)
        def submit(suffix,target):
            with SessionLocal(bind=engine) as db:
                user=db.get(User,user_id)
                payload=CalibrationIn(client_op_id=prefix+suffix,adjustment_id=prefix+suffix,
                    target_cny=target,basis_token=token,effective_on=date(2026,9,1))
                start.wait(timeout=10)
                try:return calibrate(db,user,prefix,payload)
                except HTTPException as exc:return exc.status_code,exc.detail['code']
        with ThreadPoolExecutor(max_workers=2) as pool:
            a=pool.submit(submit,'a',125);b=pool.submit(submit,'b',130)
            results=[a.result(timeout=20),b.result(timeout=20)]
        assert len([row for row in results if isinstance(row,dict)])==1
        assert (409,'balance_changed') in results
        with SessionLocal(bind=engine) as db:
            assert db.query(Transaction).filter_by(user_id=user_id).count()==1
            assert db.get(User,user_id).sync_version==2
    finally:cleanup(engine,user_id)


def test_postgres_month_end_cache_and_backfill_share_the_replay(postgres_case):
    engine,prefix,user_id=postgres_case
    try:
        with SessionLocal(bind=engine) as db:
            user=db.get(User,user_id)
            create_account(db,user,AccountIn(id=prefix,name=prefix,opening_balance=100))
            token=issue(db,user,prefix,date(2026,10,1),protocol=2)['basis_token']
            calibrate(db,user,prefix,CalibrationIn(client_op_id=prefix+'adj',adjustment_id=prefix+'adj',
                target_cny=150,basis_token=token,effective_on=date(2026,10,1)))
            assert _save_net_worth_snapshot(db,user,'2026-09')['net_worth_cny']==100
            db.commit()
            create_transaction(db,user,TransactionIn(id=prefix+'expense',client_op_id=prefix+'expense',
                kind='expense',amount=20,account_id=prefix,occurred_on=date(2026,9,15)))
            assert db.query(NetWorthSnapshot).filter_by(user_id=user_id).count()==0
            report=_save_net_worth_snapshot(db,user,'2026-09')
            current=wealth_snapshot(db,user,as_of_date=date(2026,9,30))
            assert report['net_worth_cny']==current['net_worth']==80
            db.commit()
    finally:cleanup(engine,user_id)
