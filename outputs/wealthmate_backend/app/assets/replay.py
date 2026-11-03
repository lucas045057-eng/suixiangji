"""One raw six-place CNY replay for calibration and wealth display."""
from decimal import Decimal


def account_balance(account, rows, *, include_adjustments=True):
    opening = account.opening_balance if account.currency == "CNY" else account.opening_cny_amount
    balance = opening if opening is not None else Decimal(0)
    pending = int(opening is None)
    for row in rows:
        if row.deleted_at is not None or (row.kind == "adjustment" and not include_adjustments):
            continue
        related = account.id in (row.account_id, row.from_account_id, row.to_account_id)
        if not related:
            continue
        value = row.cny_amount if row.cny_amount is not None else (row.amount if row.currency == "CNY" else None)
        if value is None:
            pending += 1
            continue
        if row.kind == "adjustment":
            if row.account_id == account.id:
                balance += value
        elif row.kind == "transfer":
            if row.from_account_id == account.id:
                balance -= value
            if row.to_account_id == account.id:
                balance += value
        elif row.account_id == account.id:
            if account.kind == "liability":
                balance += value if row.kind == "expense" else -value
            else:
                balance += value if row.kind == "income" else -value
    return balance, pending
