from copy import deepcopy
from datetime import date, datetime, timezone
from decimal import Decimal

import pytest

from app.assets import basis
from app.models import User, Account, Transaction, SyncOperation, NetWorthSnapshot, ExchangeRate
from test_adjustments import api, account, post, H, D


@pytest.fixture(autouse=True)
def reset_limiter():
    from app.core.rate_limit import auth_limiter
    auth_limiter.clear()
    yield
    auth_limiter.clear()


def get_basis(client,identifier='a',day='2026-09-01'):
    response=client.get(f'/assets/accounts/{identifier}/balance-basis?effective_on={day}',headers=H)
    assert response.status_code==200,response.text
    return response.json()


def calibrate(client,token,identifier='adjust',account_id='a',day='2026-09-01',target='125.00',**extra):
    return client.post(f'/assets/accounts/{account_id}/calibration',headers=H,json=dict(
        client_op_id=identifier+'-op',adjustment_id=identifier,basis_token=token,
        target_cny=target,effective_on=day,**extra))


def transaction(client,identifier,amount=1,day='2026-09-01',account_id='a'):
    response=client.post('/transactions',json=dict(id=identifier,client_op_id=identifier+'-op',
        kind='expense',amount=amount,account_id=account_id,occurred_on=day))
    assert response.status_code==200,response.text
    return response.json()


def state(sessions):
    with sessions() as db:
        return (db.get(User,'u').sync_version,db.query(Transaction).count(),db.query(SyncOperation).count())


def test_token_string_balance_is_authoritative_over_double_baseline(api):
    client,sessions=api;account(client)
    data=get_basis(client)
    assert data['balance_cny']=='100.000000' and data['basis_version']==1 and data['ttl_seconds']==600
    response=calibrate(client,data['basis_token'],expected_current_cny=100.00000000000001)
    assert response.status_code==200,response.text
    body=response.json()
    assert Decimal(body['amount'])==25 and body['adjustment_meta']['basis_balance_cny']=='100.000000'
    assert len(body['adjustment_meta']['basis_token_hash'])==64
    with sessions() as db:
        assert db.get(Account,'a').opening_balance==100 and db.get(Account,'a').server_version==1


def test_expired_token_rejected_but_accepted_command_replays_after_expiry(api,monkeypatch):
    client,sessions=api;account(client)
    now=basis._now();data=get_basis(client)
    accepted=calibrate(client,data['basis_token'])
    assert accepted.status_code==200
    before=state(sessions)
    monkeypatch.setattr(basis,'_now',lambda:now+601)
    assert calibrate(client,data['basis_token']).json()==accepted.json()
    assert state(sessions)==before
    expired=calibrate(client,data['basis_token'],identifier='expired')
    assert expired.status_code==409 and expired.json()['code']=='basis_expired'
    assert state(sessions)==before


@pytest.mark.parametrize('kind',['empty_parts','payload','signature','nonsense'])
def test_modified_or_malformed_token_is_400_zero_write(api,kind):
    client,sessions=api;account(client);token=get_basis(client)['basis_token']
    pieces=token.split('.')
    if kind=='empty_parts':token='b1..'
    elif kind=='payload':token=pieces[0]+'.'+('A' if pieces[1][0]!='A' else 'B')+pieces[1][1:]+'.'+pieces[2]
    elif kind=='signature':token='.'.join(pieces[:2])+'.'+('A' if pieces[2][0]!='A' else 'B')+pieces[2][1:]
    else:token='not-a-token'
    before=state(sessions);response=calibrate(client,token)
    assert response.status_code==400 and response.json()['code']=='invalid_basis_token'
    assert state(sessions)==before


def test_account_user_and_date_scope_cannot_be_reused(api):
    client,sessions=api;account(client);account(client,'b')
    token=get_basis(client)['basis_token'];before=state(sessions)
    for values in [dict(account_id='b'),dict(day='2026-09-02')]:
        response=calibrate(client,token,**values)
        assert response.status_code==422 and response.json()['code']=='basis_scope_mismatch'
    with pytest.raises(Exception) as caught:basis.verify(token,'other','a',D)
    assert caught.value.status_code==422 and caught.value.detail['code']=='basis_scope_mismatch'
    assert state(sessions)==before


def test_financial_change_invalidates_even_when_balance_is_equal(api):
    client,sessions=api;account(client);token=get_basis(client)['basis_token']
    transaction(client,'expense',5)
    response=client.post('/transactions',json=dict(id='income',client_op_id='income-op',kind='income',
        amount=5,account_id='a',occurred_on='2026-09-01'))
    assert response.status_code==200
    assert get_basis(client)['balance_cny']=='100.000000'
    before=state(sessions);response=calibrate(client,token)
    assert response.status_code==409 and response.json()['code']=='balance_changed'
    assert state(sessions)==before


def test_metadata_other_accounts_and_future_transactions_do_not_invalidate(api):
    client,_=api;account(client);account(client,'b');token=get_basis(client)['basis_token']
    assert client.patch('/accounts/a',json={'name':'renamed','note':'metadata'}).status_code==200
    transaction(client,'other',day='2026-09-01',account_id='b')
    transaction(client,'future',day='2026-09-02')
    assert calibrate(client,token).status_code==200


def test_legacy_expected_current_path_remains_valid(api):
    client,sessions=api;account(client)
    result=post(client)
    assert result.status_code==200 and Decimal(result.json()['amount'])==25
    assert 'basis_token_hash' not in result.json()['adjustment_meta']
    with sessions() as db:assert db.query(Transaction).count()==1


def test_month_end_replay_cache_backfill_and_legacy_shape(api):
    client,sessions=api;account(client)
    token=get_basis(client,day='2026-10-01')['basis_token']
    assert calibrate(client,token,day='2026-10-01',target='150.00').status_code==200
    before=client.get('/wealth?as_of_date=2026-09-30',headers=H).json()
    after=client.get('/wealth?as_of_date=2026-10-01',headers=H).json()
    assert before['net_worth']==100 and after['net_worth']==150
    assert before['excludes_later_adjustments'] and before['valuation_mode']=='frozen_cny_book_value'
    report=client.get('/reports/monthly/2026-09',headers=H)
    assert report.status_code==200,report.text
    assert report.json()['net_worth_snapshot']['as_of_date']=='2026-09-30'
    assert report.json()['net_worth_snapshot']['net_worth_cny']==100
    transaction(client,'backfilled',20,day='2026-09-10')
    with sessions() as db:assert db.query(NetWorthSnapshot).count()==0
    cached=client.get('/reports/monthly/2026-09',headers=H)
    assert cached.json()['net_worth_snapshot']['net_worth_cny']==80
    assert cached.json()['summary']==report.json()['summary']
    assert client.get('/wealth?as_of_date=2026-10-01',headers=H).json()['net_worth']==130
    legacy=client.get('/wealth?as_of_date=2026-09-30').json()
    assert set(legacy)=={'total_assets','total_liabilities','net_worth','accounts','server_version','pending_conversion_count'}
    assert 'net_worth_snapshot' not in client.get('/reports/monthly/2026-09').json()


def test_foreign_dated_stored_snapshot_and_missing_snapshot_pending(api):
    client,sessions=api
    account(client,currency='USD',opening_rate_date='2026-09-01',opening_exchange_rate=7)
    with sessions.begin() as db:db.get(Account,'a').opening_cny_amount=None
    missing=client.get('/wealth?as_of_date=2026-08-31',headers=H).json()
    known=client.get('/wealth?as_of_date=2026-09-01',headers=H).json()
    assert missing['net_worth'] is None and missing['pending_conversion_count']==1
    assert missing['accounts'][0]['cny_balance'] is None
    assert known['net_worth']==700 and known['pending_conversion_count']==0
    assert get_basis(client)['balance_cny']=='700.000000'
    # A later candidate does not revalue the stored September rate.
    with sessions.begin() as db:
        db.add(ExchangeRate(base_currency='USD',quote_currency='CNY',rate=99,rate_date=date(2026,9,2),source='candidate'))
    assert client.get('/wealth?as_of_date=2026-09-02',headers=H).json()['net_worth']==700
    account(client,'unknown',currency='GBP')
    value=client.get('/wealth?as_of_date=2026-09-30',headers=H).json()
    assert value['total_assets'] is None and value['known_total_assets']==700 and value['net_worth'] is None
    pending=client.get('/assets/accounts/unknown/balance-basis?effective_on=2026-09-30',headers=H)
    assert pending.status_code==409 and pending.json()['code']=='conversion_pending'


def test_historical_liability_signs_and_archive_membership(api):
    client,_=api;account(client,kind='liability')
    token=get_basis(client)['basis_token']
    assert calibrate(client,token,target='150.00').status_code==200
    assert client.patch('/accounts/a',json={'archived_at':'2026-10-01T00:00:00Z'}).status_code==200
    past=client.get('/wealth?as_of_date=2026-09-30',headers=H).json()
    archived=client.get('/wealth?as_of_date=2026-10-01',headers=H).json()
    assert past['total_liabilities']==150 and past['net_worth']==-150
    assert archived['accounts']==[] and archived['net_worth']==0


def test_same_restore_id_writes_nothing_new_id_keeps_rows_and_adds_one_receipt(api):
    client,sessions=api;account(client);post(client)
    payload=client.get('/backup/export',headers=H).json();payload['restore_id']='first'
    first=client.post('/backup/restore',headers=H,json=payload)
    assert first.status_code==200,first.text
    before=state(sessions)
    assert client.post('/backup/restore',headers=H,json=payload).json()['replayed']
    assert state(sessions)==before
    payload['restore_id']='second'
    assert client.post('/backup/restore',headers=H,json=payload).status_code==200
    after=state(sessions)
    assert after[1]==before[1] and after[2]==before[2]+1


def test_new_pending_transaction_invalidates_existing_basis_without_zero_fallback(api):
    client,sessions=api;account(client);token=get_basis(client)['basis_token']
    response=client.post('/transactions',json=dict(id='pending',client_op_id='pending-op',kind='expense',
        amount=1,currency='GBP',account_id='a',occurred_on='2026-09-01'))
    assert response.status_code==200,response.text
    before=state(sessions)
    response=calibrate(client,token)
    assert response.status_code==409 and response.json()['code']=='balance_changed'
    assert state(sessions)==before
    pending=client.get('/assets/accounts/a/balance-basis?effective_on=2026-09-01',headers=H)
    assert pending.status_code==409 and pending.json()['code']=='conversion_pending'


def test_backdated_edit_invalidates_both_months_and_metadata_keeps_cache(api):
    client,sessions=api;account(client);transaction(client,'dated',20,day='2026-09-15')
    for month in ['2026-09','2026-10']:
        response=client.get('/reports/monthly/'+month,headers=H)
        assert response.status_code==200 and response.json()['net_worth_snapshot']['net_worth_cny']==80
    assert client.patch('/accounts/a',json={'name':'metadata only'}).status_code==200
    with sessions() as db:assert db.query(NetWorthSnapshot).count()==2
    moved=client.patch('/transactions/dated',json=dict(id='dated',client_op_id='move-op',kind='expense',
        amount=20,account_id='a',occurred_on='2026-10-15'))
    assert moved.status_code==200,moved.text
    with sessions() as db:assert db.query(NetWorthSnapshot).count()==0
    assert client.get('/reports/monthly/2026-09',headers=H).json()['net_worth_snapshot']['net_worth_cny']==100
    assert client.get('/reports/monthly/2026-10',headers=H).json()['net_worth_snapshot']['net_worth_cny']==80
    assert client.delete('/transactions/dated').status_code==200
    with sessions() as db:assert [row.month for row in db.query(NetWorthSnapshot).all()]==['2026-09']
    assert client.get('/reports/monthly/2026-10',headers=H).json()['net_worth_snapshot']['net_worth_cny']==100
