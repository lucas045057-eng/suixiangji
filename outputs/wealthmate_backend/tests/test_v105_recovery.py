from datetime import date
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.db import Base, get_db
from app.models import User, Transaction
from app.auth import service
from app.core.security import hash_password, create_token, verify_password
from app.core.rate_limit import auth_limiter


@pytest.fixture
def recovery_case(monkeypatch):
    monkeypatch.setenv('WEALTHMATE_ENVIRONMENT','test')
    monkeypatch.setenv('WEALTHMATE_JWT_SECRET','synthetic-recovery-test-secret')
    from app.config import get_settings
    get_settings.cache_clear();auth_limiter.clear()
    engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
    Base.metadata.create_all(engine)
    db=Session(engine,expire_on_commit=False)
    user=User(id='owner',username='owner',password_hash=hash_password('old-password'),sync_version=7)
    other=User(id='other',username='other',password_hash=hash_password('other-password'))
    db.add_all([user,other,Transaction(id='history',user_id='owner',client_op_id='history',kind='expense',amount=16,currency='CNY',occurred_on=date(2026,9,1),server_version=7)])
    db.commit()
    from app.main import app
    def override(): yield db
    app.dependency_overrides[get_db]=override
    client=TestClient(app)
    try: yield client,db,user,other
    finally:
        app.dependency_overrides.pop(get_db,None);client.close();db.close();engine.dispose();get_settings.cache_clear();auth_limiter.clear()


def issue(client,user,password='old-password'):
    return client.post('/auth/recovery-code',headers={'Authorization':'Bearer '+create_token(user.id,user.username,user.auth_version or 0)},json={'current_password':password})


def test_recovery_consumes_code_revokes_old_sessions_and_preserves_identity_data(recovery_case):
    client,db,user,other=recovery_case
    old_token=create_token(user.id,user.username,user.auth_version or 0)
    response=issue(client,user)
    assert response.status_code==200,response.text
    code=response.json()['recovery_code']
    assert len(code.replace('-',''))>=48
    assert code not in user.recovery_code_hash
    assert client.get('/auth/me',headers={'Authorization':'Bearer '+old_token}).json()['recovery_configured'] is True
    reset=client.post('/auth/recover',json={'username':' OWNER ','recovery_code':code,'new_password':'new-password'})
    assert reset.status_code==200,reset.text
    assert reset.json()=={'reset':True}
    assert client.get('/auth/me',headers={'Authorization':'Bearer '+old_token}).status_code==401
    assert client.post('/auth/login',json={'username':'owner','password':'new-password'}).json()['user_id']=='owner'
    assert db.get(Transaction,'history').amount==16
    assert db.get(User,'owner').sync_version==7
    assert verify_password('other-password',db.get(User,'other').password_hash)
    replay=client.post('/auth/recover',json={'username':'owner','recovery_code':code,'new_password':'second-password'})
    assert replay.status_code==400


def test_wrong_password_cannot_rotate_and_unknown_or_wrong_code_return_same_error(recovery_case):
    client,db,user,other=recovery_case
    assert issue(client,user,'wrong-password').status_code==401
    errors=[]
    for name in ['owner','unknown']:
        response=client.post('/auth/recover',json={'username':name,'recovery_code':'WRONG-CODE','new_password':'new-password'})
        assert response.status_code==400
        errors.append(response.json())
    assert errors[0]==errors[1]
    assert verify_password('old-password',db.get(User,'owner').password_hash)


def test_rotating_invalidates_previous_code_and_short_password_does_not_consume(recovery_case):
    client,db,user,other=recovery_case
    first=issue(client,user).json()['recovery_code']
    second=issue(client,user).json()['recovery_code']
    assert first!=second
    assert client.post('/auth/recover',json={'username':'owner','recovery_code':first,'new_password':'new-password'}).status_code==400
    assert client.post('/auth/recover',json={'username':'owner','recovery_code':second,'new_password':'short'}).status_code==422
    assert client.post('/auth/recover',json={'username':'owner','recovery_code':second,'new_password':'new-password'}).status_code==200


def test_recovery_endpoint_is_rate_limited(recovery_case,monkeypatch):
    client,db,user,other=recovery_case
    monkeypatch.setenv('WEALTHMATE_AUTH_LOGIN_LIMIT','2')
    from app.config import get_settings
    get_settings.cache_clear()
    body={'username':'owner','recovery_code':'wrong','new_password':'new-password'}
    assert [client.post('/auth/recover',json=body).status_code for _ in range(3)]==[400,400,429]
