from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from fastapi import HTTPException
from app.db import SessionLocal
from app.models import User
from app.auth.schemas import PasswordRecoverIn
from app.auth.service import recover_password
from app.core.security import hash_password,verify_password
from test_sync_postgres_concurrency import postgres_case

def test_real_postgres_consumes_recovery_code_once_under_race(postgres_case):
    engine,prefix,user_id=postgres_case
    code='A'*48
    with SessionLocal(bind=engine) as db:
        user=db.get(User,user_id);user.recovery_code_hash=hash_password(code)
        username=user.username;db.commit()
    barrier=Barrier(2)
    def reset():
        with SessionLocal(bind=engine) as db:
            barrier.wait(timeout=10)
            try:
                recover_password(db,PasswordRecoverIn(username=username,recovery_code=code,new_password='new-synthetic-password'))
                return True
            except HTTPException as exc:
                assert exc.status_code==400
                return False
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda _:reset(),range(2)))
    assert sorted(results)==[False,True]
    with SessionLocal(bind=engine) as db:
        user=db.get(User,user_id)
        assert user.auth_version==1
        assert user.recovery_code_hash is None
        assert verify_password('new-synthetic-password',user.password_hash)
