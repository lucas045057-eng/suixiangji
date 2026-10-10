from datetime import date
from decimal import Decimal
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from app.db import Base
from app.models import User, Budget
from app.insights.domain import TransactionRecord, monthly_metrics, period_metrics
from app.sync.service import push, pull
from app.sync.schemas import SyncPushIn


def test_chart_and_month_use_business_date_even_when_timestamp_differs():
    rows=[TransactionRecord('meal','expense',Decimal('16'),'CNY',Decimal('16'),'餐饮',date(2026,9,30),occurred_at='2026-10-01T12:00:00'),
          TransactionRecord('pending','expense',Decimal('2'),'HKD',None,None,date(2026,9,1)),
          TransactionRecord('transfer','transfer',Decimal('500'),'CNY',Decimal('500'),None,date(2026,9,1))]
    monthly=monthly_metrics(rows,'2026-09')
    period=period_metrics(rows,'month',date(2026,9,1),date(2026,9,30))
    assert monthly['expense']==period['expense_total']==16
    assert sum(p['expense'] for p in period['expense_series'])==16
    assert monthly['pending_conversion_count']==period['pending_conversion_count']==1


def test_total_budget_sync_needs_no_category_and_replays_idempotently():
    engine=create_engine('sqlite:///:memory:'); Base.metadata.create_all(engine)
    with Session(engine,expire_on_commit=False) as db:
        user=User(id='budget-owner',username='budget-owner',password_hash='synthetic',sync_version=0)
        db.add(user);db.commit()
        payload=SyncPushIn(operations=[dict(client_op_id='total-op',entity='budgets',entity_id='total',type='upsert',payload=dict(month='2026-09',category_id='__total__',limit=100))])
        result=push(payload,db,user)
        assert result['accepted'][0]['server_version']==1
        assert pull(0,db,user)['budgets'][0]['category_id']=='__total__'
        assert push(payload,db,user)['server_version']==1
        assert db.query(Budget).count()==1
    engine.dispose()

def test_legacy_cny_without_conversion_snapshot_is_known_in_all_aggregates():
    rows=[TransactionRecord('legacy','expense',Decimal('16'),'CNY',None,'餐饮',date(2026,9,1))]
    month=monthly_metrics(rows,'2026-09')
    period=period_metrics(rows,'month',date(2026,9,1),date(2026,9,30))
    assert month['expense']==period['expense_total']==16
    assert month['pending_conversion_count']==period['pending_conversion_count']==0
    from app.models import Account,Transaction
    from app.assets.service import wealth
    engine=create_engine('sqlite:///:memory:');Base.metadata.create_all(engine)
    with Session(engine,expire_on_commit=False) as db:
        user=User(id='legacy',username='legacy',password_hash='synthetic',sync_version=0)
        db.add_all([user,Account(id='legacy-account',user_id='legacy',name='卡',kind='asset',currency='CNY',opening_balance=100),
          Transaction(id='legacy',user_id='legacy',client_op_id='legacy',account_id='legacy-account',kind='expense',amount=16,currency='CNY',cny_amount=None,occurred_on=date(2026,9,1))])
        db.commit()
        assert wealth(db,user)['net_worth']==84
        assert wealth(db,user)['pending_conversion_count']==0
    engine.dispose()
