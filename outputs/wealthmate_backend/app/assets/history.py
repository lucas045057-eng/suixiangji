"""Invalidate affected month-end caches across REST, sync and restore writers."""
from sqlalchemy import event, inspect, delete
from sqlalchemy.orm import Session
from ..models import Account, Transaction, NetWorthSnapshot

ACCOUNT_FIELDS = {"kind", "currency", "opening_balance", "opening_cny_amount", "opening_exchange_rate",
                  "opening_rate_date", "archived_at", "deleted_at"}
TRANSACTION_FIELDS = {"kind", "amount", "currency", "cny_amount", "account_id", "from_account_id",
                      "to_account_id", "occurred_on", "deleted_at"}


@event.listens_for(Session, "before_flush")
def invalidate_snapshots(session, _context, _instances):
    affected = {}
    for row in set(session.new) | set(session.dirty) | set(session.deleted):
        if not isinstance(row, (Account, Transaction)) or row.user_id is None:
            continue
        state = inspect(row)
        fields = ACCOUNT_FIELDS if isinstance(row, Account) else TRANSACTION_FIELDS
        if not (state.pending or row in session.deleted or any(state.attrs[k].history.has_changes() for k in fields)):
            continue
        month = None
        if isinstance(row, Transaction):
            days = [row.occurred_on, *state.attrs.occurred_on.history.deleted]
            days = [day for day in days if day is not None]
            if days:
                month = min(days).strftime("%Y-%m")
        previous = affected.get(row.user_id, month)
        affected[row.user_id] = None if previous is None or month is None else min(previous, month)
    for user_id, month in affected.items():
        statement = delete(NetWorthSnapshot).where(NetWorthSnapshot.user_id == user_id)
        if month is not None:
            statement = statement.where(NetWorthSnapshot.month >= month)
        session.execute(statement.execution_options(synchronize_session="fetch"))
