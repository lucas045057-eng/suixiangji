from datetime import date
from decimal import Decimal
import importlib.util
from pathlib import Path
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, text, select, delete
from sqlalchemy.orm import Session
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.operations import Operations
from app.db import Base
from app.models import Account, AccountMutationAudit, SyncOperation, Transaction, User
from app.assets.names import normalize_account_name, available_account_name
from app.assets.schemas import AccountIn, AccountPatch
from app.assets.service import save_account, create_account, update_account, delete_account
from app.sync.schemas import SyncPushIn
from app.sync.service import push
from test_sync_postgres_concurrency import postgres_case

@pytest.fixture
def db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine, expire_on_commit=False) as session:
        session.add(User(id="owner", username="owner", password_hash="synthetic"))
        session.commit()
        yield session
    engine.dispose()

def op(identifier, payload=None, operation_id=None, kind="upsert"):
    return dict(client_op_id=operation_id or identifier + "-op", entity="accounts",
                entity_id=identifier, type=kind, payload=payload or {})

def upload(db, *operations):
    return push(SyncPushIn(operations=list(operations)), db, db.get(User, "owner"))

def tx(identifier, account):
    return dict(client_op_id=identifier, entity="transactions", entity_id=identifier, type="upsert",
        payload=dict(type="expense", account_id=account, amount=3, occurred_on="2026-10-01"))

def test_patch_delete_and_missing_delete_preserve_financial_fields(db):
    user = db.get(User, "owner")
    values = dict(id="fx", name="FX", kind="liability", currency="USD", opening_balance="123.456789",
        opening_cny_amount="888.123456", opening_exchange_rate="7.1234567890",
        opening_rate_date="2026-10-01", opening_rate_source="stored", is_liquid=True,
        account_kind="loan", is_default_payment=True)
    row = save_account(db, user, values, server_version=1)
    db.commit()
    expected = {k: getattr(row,k) for k in values if k not in {"id","name"}}
    update_account(db, user, "fx", AccountPatch(note="purpose"))
    upload(db, op("fx", {"archived_at":"2026-10-02T12:00:00"}, "archive"))
    assert {k:getattr(row,k) for k in expected} == expected
    upload(db, op("fx", {"opening_balance":0,"name":"ignored"}, "delete", "delete"))
    assert row.deleted_at is not None and row.name == "FX" and row.note == "purpose"
    assert {k:getattr(row,k) for k in expected} == expected
    upload(db, op("missing", kind="delete"))
    assert db.get(Account,"missing") is None
    upload(db, op("fx", {"note":"after"}, "no-resurrection"))
    assert row.deleted_at is not None

def test_duplicate_names_keep_ids_amounts_links_and_stable_replay(db):
    upload(db, op("first", {"name":"Card","opening_balance":100}))
    operations = [tx("tx", "second-id"), op("second-id", {"name":"  ＣＡＲＤ  ","opening_balance":200})]
    result = upload(db,*operations)
    assert len(result["accepted"]) == 2 and not result["conflicts"]
    row = db.get(Account,"second-id")
    assert row.name.endswith("·second-i") and row.opening_balance == 200
    assert db.get(Account,"first").opening_balance == 100
    assert db.get(Transaction,"tx").account_id == row.id
    before = row.name, row.server_version, result["server_version"]
    replay = upload(db,*operations)
    assert (row.name,row.server_version,replay["server_version"]) == before
    assert all(not item["created"] for item in replay["accepted"])
    audit = db.query(AccountMutationAudit).one()
    assert audit.before_json == {"name":"  ＣＡＲＤ  "}
    assert audit.after_json == {"name":row.name}
    occupied = {normalize_account_name("Card"),normalize_account_name("Card ·second-i")}
    assert available_account_name("Card","second-id",occupied).endswith("-1")
    assert len(available_account_name("x"*128,"second-id",{"x"*128})) <= 128

@pytest.mark.parametrize("invalid", ["not-a-date",123,{},[],True])
def test_metadata_repairs_and_complete_audits(db,invalid):
    note = "😀"*300
    result = upload(db,op("new",dict(name="new",note=note,archived_at=invalid)))
    assert len(result["accepted"]) == 1 and not result["conflicts"]
    row = db.get(Account,"new")
    assert row.note == note[:256] and row.archived_at is None
    upload(db,op("new",{"archived_at":"2026-10-01T10:00:00"},"valid"))
    archived = row.archived_at
    upload(db,op("new",{"archived_at":invalid},"invalid-update"))
    assert row.archived_at == archived
    audits = db.query(AccountMutationAudit).all()
    assert len(audits) == 3
    assert all(a.user_id=="owner" and a.account_id=="new" and a.reason for a in audits)
    assert next(a for a in audits if a.event_kind=="v1_note_truncated").before_json == {"note":note}
    assert next(a for a in audits if a.client_op_id=="invalid-update").after_json == {"archived_at":archived.isoformat()}
    upload(db,op("new",{"archived_at":invalid},"invalid-update"))
    assert db.query(AccountMutationAudit).count() == 3

def test_rest_remains_strict_and_tombstone_releases_name(db):
    user=db.get(User,"owner")
    create_account(db,user,AccountIn(id="one",name="Card"))
    with pytest.raises(HTTPException) as error:
        create_account(db,user,AccountIn(id="two",name="ＣＡＲＤ"))
    assert error.value.status_code == 409
    db.rollback()
    delete_account(db,user,"one")
    create_account(db,user,AccountIn(id="two",name="Card"))
    assert db.get(Account,"one").deleted_at is not None
    assert db.get(Account,"two").deleted_at is None

def test_real_reference_failure_rolls_back_repairs_receipts_and_watermark(db):
    upload(db,op("one",{"name":"Card"}))
    watermark=db.get(User,"owner").sync_version
    with pytest.raises(HTTPException):
        upload(db,op("two",{"name":"Card","note":"x"*300}),tx("bad","absent"))
    assert db.get(Account,"two") is None
    assert db.query(AccountMutationAudit).count()==0
    assert db.query(SyncOperation).count()==1
    assert db.get(User,"owner").sync_version==watermark

def test_migration_is_idempotent_and_preserves_money_ids_and_links(tmp_path,monkeypatch):
    url=f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setenv("WEALTHMATE_DATABASE_URL",url)
    from app.config import get_settings
    get_settings.cache_clear()
    cfg=Config(str(Path(__file__).resolve().parents[1]/"alembic.ini"))
    command.upgrade(cfg,"0004_v105_recovery")
    engine=create_engine(url)
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,username,password_hash,display_name,quick_memories,auth_version,sync_version) VALUES ('u','u','test','u','[]',0,42)"))
        for identifier,name,version in [("a","Card",1),("b","ＣＡＲＤ",2),("c","Card ·b",3)]:
            c.execute(text("INSERT INTO accounts(id,user_id,name,kind,account_kind,currency,opening_balance,is_liquid,is_default_payment,server_version) VALUES (:id,'u',:name,'asset','other','USD',123.456789,0,0,:version)"),dict(id=identifier,name=name,version=version))
        c.execute(text("INSERT INTO transactions(id,user_id,client_op_id,kind,amount,currency,account_id,occurred_on,conversion_status,server_version) VALUES ('t','u','t','expense',2,'CNY','b','2026-10-01','ready',4)"))
    command.upgrade(cfg,"head")
    spec=importlib.util.spec_from_file_location("migration_p1",Path(__file__).resolve().parents[1]/"migrations/versions/0005_v110_account_safety.py")
    migration=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    with engine.begin() as c:
        before=c.execute(text("SELECT id,name,opening_balance,server_version FROM accounts ORDER BY id")).all()
        assert before[0]==("a","Card",123.456789,1)
        assert before[1][1].endswith("·b-1") and before[1][3]==43
        assert c.execute(text("SELECT account_id FROM transactions")).scalar()=="b"
        with Operations.context(MigrationContext.configure(c)):
            migration.upgrade()
        assert c.execute(text("SELECT id,name,opening_balance,server_version FROM accounts ORDER BY id")).all()==before
        assert c.execute(text("SELECT count(*) FROM account_mutation_audits")).scalar()==1
        assert c.execute(text("SELECT sync_version FROM users")).scalar()==43
    engine.dispose()
    get_settings.cache_clear()

def test_postgres_same_name_concurrent_pushes(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from app.db import SessionLocal
    engine,prefix,user_id=postgres_case
    start=Barrier(2)
    def write(suffix):
        identifier=prefix+suffix
        operations=[op(identifier,{"name":"shared","opening_balance":123}),tx(identifier+"tx",identifier)]
        with SessionLocal(bind=engine) as s:
            user=s.get(User,user_id)
            start.wait(timeout=10)
            result=push(SyncPushIn(operations=operations),s,user)
            replay=push(SyncPushIn(operations=operations),s,user)
            assert all(not a["created"] for a in replay["accepted"])
            return result
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(write,["a","b"]))
        assert all(len(r["accepted"])==2 and not r["conflicts"] for r in results)
        with SessionLocal(bind=engine) as s:
            rows=s.scalars(select(Account).where(Account.user_id==user_id)).all()
            assert len(rows)==2 and len({r.normalized_name for r in rows})==2
            assert all(r.opening_balance==123 for r in rows)
            assert {t.account_id for t in s.scalars(select(Transaction).where(Transaction.user_id==user_id))}=={r.id for r in rows}
            assert s.query(AccountMutationAudit).filter_by(user_id=user_id).count()==1
            assert s.get(User,user_id).sync_version==4
    finally:
        with SessionLocal(bind=engine) as s:
            for model in (Transaction,AccountMutationAudit,Account):
                s.execute(delete(model).where(model.user_id==user_id))
            s.commit()


def test_database_index_enforces_normalized_live_name_and_archive_keeps_name(db):
    from sqlalchemy.exc import IntegrityError
    user=db.get(User,"owner")
    row=save_account(db,user,dict(id="one",name="Straße",archived_at="2026-10-01T00:00:00"))
    db.commit()
    assert row.normalized_name=="strasse"
    db.add(Account(id="two",user_id=user.id,name="STRASSE"))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()
    result=upload(db,op("two",{"name":"STRASSE"}))
    assert result["accepted"] and db.get(Account,"two").name.endswith("·two")


def test_empty_name_is_accepted_with_audited_stable_fallback(db):
    result=upload(db,op("empty",{"name":"   "}))
    assert len(result["accepted"])==1
    assert db.get(Account,"empty").name=="账户 ·empty"
    assert db.query(AccountMutationAudit).one().before_json=={"name":"   "}


def test_shared_lock_rechecks_auth_and_has_readable_error(db):
    from app.core.financial_lock import lock_current_user
    with pytest.raises(HTTPException) as error:
        lock_current_user(db,"owner",verified_auth_version=1)
    assert error.value.status_code==401
    assert error.value.detail=="登录已失效，请重新登录"


def test_postgres_rest_and_sync_serialize_validation_and_versions(postgres_case):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event
    from sqlalchemy import event
    from app.db import SessionLocal
    from app.core.financial_lock import lock_current_user
    engine,prefix,user_id=postgres_case
    waiting=Event()
    rest_id=prefix+"rest"
    sync_id=prefix+"sync"
    def reached_lock(_conn,_cursor,statement,_parameters,_context,_many):
        if "FOR UPDATE" in statement:
            waiting.set()
    sync_session=SessionLocal(bind=engine)
    stale_user=sync_session.get(User,user_id)
    try:
        with SessionLocal(bind=engine) as rest, ThreadPoolExecutor(max_workers=1) as pool:
            user=lock_current_user(rest,user_id)
            event.listen(engine,"before_cursor_execute",reached_lock)
            future=pool.submit(push,SyncPushIn(operations=[op(sync_id,{"name":"same","opening_balance":22}),tx(sync_id+"tx",sync_id)]),sync_session,stale_user)
            assert waiting.wait(timeout=10)
            create_account(rest,user,AccountIn(id=rest_id,name="same",opening_balance=11))
            result=future.result(timeout=15)
            assert len(result["accepted"])==2 and not result["conflicts"]
        with SessionLocal(bind=engine) as s:
            a=s.get(Account,rest_id)
            b=s.get(Account,sync_id)
            assert a.name=="same" and b.name.startswith("same ·")
            assert (a.opening_balance,b.opening_balance)==(11,22)
            assert a.server_version==1 and b.server_version==2
            assert s.get(Transaction,sync_id+"tx").account_id==sync_id
            assert s.get(User,user_id).sync_version==3
    finally:
        event.remove(engine,"before_cursor_execute",reached_lock)
        sync_session.close()
        with SessionLocal(bind=engine) as s:
            for model in (Transaction,AccountMutationAudit,Account):
                s.execute(delete(model).where(model.user_id==user_id))
            s.commit()


def test_opening_only_update_does_not_rewrite_absent_snapshot(db):
    user=db.get(User,"owner")
    row=save_account(db,user,dict(id="cny",name="CNY",opening_balance=10))
    db.commit()
    update_account(db,user,"cny",AccountPatch(opening_balance=20))
    assert row.opening_balance==20 and row.opening_cny_amount==10


@pytest.mark.parametrize("invalid", [123,True,{},[],"123","not-a-date"])
def test_rest_archive_schema_is_strict(invalid):
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        AccountPatch(archived_at=invalid)
