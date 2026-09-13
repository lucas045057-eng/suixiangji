from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy.orm import Session

from ..assets.service import account_json, save_account
from ..ledger.service import (
    attach_latest_rate,
    normalise_transaction_payload,
    save_transaction,
    transaction_json,
)
from ..models import Account, Transaction, User
from .schemas import RestoreIn


def export_backup(db: Session, user: User) -> dict:
    accounts = db.query(Account).filter(Account.user_id == user.id).all()
    transactions = db.query(Transaction).filter(Transaction.user_id == user.id).all()
    return {
        "schema_version": 1,
        "exported_at": datetime.now(timezone.utc),
        "accounts": [account_json(row) for row in accounts],
        "transactions": [transaction_json(row) for row in transactions],
    }


def restore_backup(payload: RestoreIn, db: Session, user: User) -> dict:
    imported_accounts = 0
    imported_transactions = 0
    for item in payload.accounts:
        data = dict(item)
        data["id"] = data.get("id") or str(uuid4())
        data.setdefault("name", data["id"])
        save_account(db, user, data)
        imported_accounts += 1
    for item in payload.transactions:
        data = normalise_transaction_payload(attach_latest_rate(db, dict(item)))
        save_transaction(db, user, data, deleted=bool(item.get("deleted_at")))
        imported_transactions += 1
    db.commit()
    return {
        "restored": True,
        "accounts": imported_accounts,
        "transactions": imported_transactions,
    }
