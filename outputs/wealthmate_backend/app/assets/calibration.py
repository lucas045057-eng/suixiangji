"""Dedicated immutable calibration commands; all reads/writes share a user lock."""
from datetime import datetime, timezone
from decimal import Decimal
from fastapi import HTTPException
from pydantic import ValidationError
from ..core.financial_lock import lock_current_user
from ..models import Account, Transaction, SyncOperation
from ..ledger.schemas import AdjustmentIn
from ..ledger.domain import normalise_transaction_payload
from ..ledger.service import transaction_json
from .replay import account_balance


def conflict(code, message):
    raise HTTPException(status_code=409, detail={"code": code, "message": message})


def _active_account(db, user, account_id):
    account = db.get(Account, account_id, populate_existing=True)
    if account is None or account.user_id != user.id:
        raise HTTPException(status_code=404, detail="Account not found")
    if account.deleted_at is not None or account.archived_at is not None:
        conflict("account_inactive", "Calibration requires an active account")
    return account


def _replay(db, user, account_id, payload, original_id=None):
    receipt = db.query(SyncOperation).filter_by(user_id=user.id, client_op_id=payload.client_op_id).first()
    if receipt is None:
        # Protect the shared operation namespace, including old REST transactions.
        other = db.query(Transaction.id).filter_by(user_id=user.id, client_op_id=payload.client_op_id).first()
        if other:
            conflict("operation_mismatch", "Operation ID already belongs to another transaction")
        return None
    row = db.get(Transaction, receipt.entity_id, populate_existing=True)
    matches = (receipt.entity == "transactions" and row is not None and row.user_id == user.id
               and row.kind == "adjustment" and row.account_id == account_id
               and row.id == payload.adjustment_id and row.reverses_transaction_id == original_id
               and (row.occurred_on == payload.effective_on
                    or (original_id is not None and "effective_on" not in payload.model_fields_set)))
    if matches and original_id is None:
        meta = row.adjustment_meta
        matches = (Decimal(meta["target_cny"]) == payload.target_cny
                   and Decimal(meta["basis_balance_cny"]) == payload.expected_current_cny)
    if not matches:
        conflict("operation_mismatch", "Operation ID already used for a different command")
    return transaction_json(row)


def _append(db, user, account_id, payload, delta, meta, original_id=None):
    if db.get(Transaction, payload.adjustment_id) is not None:
        conflict("adjustment_id_used", "Adjustment ID already exists")
    try:
        data = AdjustmentIn(id=payload.adjustment_id, client_op_id=payload.client_op_id,
            amount=delta, cny_amount=delta, account_id=account_id, occurred_on=payload.effective_on,
            occurred_at=datetime.now(timezone.utc).isoformat(), adjustment_meta=meta,
            reverses_transaction_id=original_id).model_dump()
    except ValidationError:
        raise HTTPException(status_code=422, detail="Adjustment delta exceeds storage precision or range") from None
    values = normalise_transaction_payload(data)
    user.sync_version += 1
    row = Transaction(user_id=user.id, **values, server_version=user.sync_version)
    db.add(row)
    db.add(SyncOperation(user_id=user.id, client_op_id=payload.client_op_id, entity="transactions",
                         entity_id=row.id, server_version=user.sync_version))
    db.flush()
    result = transaction_json(row)
    db.commit()
    return result


def calibrate(db, user, account_id, payload):
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
        replay = _replay(db, user, account_id, payload)
        if replay is not None:
            db.commit()
            return replay
        account = _active_account(db, user, account_id)
        rows = db.query(Transaction).filter(Transaction.user_id == user.id,
            Transaction.deleted_at.is_(None), Transaction.occurred_on <= payload.effective_on).all()
        current, pending = account_balance(account, rows)
        if pending:
            conflict("conversion_pending", "Complete missing CNY snapshots before calibration")
        if current != payload.expected_current_cny:
            conflict("balance_changed", "Account balance changed; reload before calibrating")
        delta = payload.target_cny - current
        if delta == 0:
            conflict("balance_unchanged", "Balance already matches target")
        meta = dict(reason="balance_calibration", target_cny=str(payload.target_cny),
            basis_balance_cny=str(current), effective_on=payload.effective_on.isoformat(),
            captured_at=datetime.now(timezone.utc).isoformat())
        return _append(db, user, account_id, payload, delta, meta)
    except BaseException:
        db.rollback()
        raise


def reverse(db, user, account_id, transaction_id, payload):
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
        replay = _replay(db, user, account_id, payload, transaction_id)
        if replay is not None:
            db.commit()
            return replay
        _active_account(db, user, account_id)
        original = db.get(Transaction, transaction_id, populate_existing=True)
        if original is None or original.user_id != user.id or original.account_id != account_id:
            raise HTTPException(status_code=404, detail="Calibration not found")
        if original.kind != "adjustment" or original.reverses_transaction_id is not None:
            conflict("not_reversible", "Only an original calibration may be reversed")
        if payload.effective_on < original.occurred_on:
            raise HTTPException(status_code=422, detail="Reversal date precedes original calibration")
        if db.query(Transaction.id).filter_by(user_id=user.id, reverses_transaction_id=original.id).first():
            conflict("already_reversed", "Calibration has already been reversed")
        meta = dict(reason="reversal", effective_on=payload.effective_on.isoformat(),
                    captured_at=datetime.now(timezone.utc).isoformat())
        return _append(db, user, account_id, payload, -original.amount, meta, original.id)
    except BaseException:
        db.rollback()
        raise
