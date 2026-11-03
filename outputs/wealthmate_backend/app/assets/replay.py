"""One Decimal CNY book-value replay for calibration, wealth and reports."""
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, localcontext
from . import history  # Register cache invalidation for every ORM financial writer.


def decimal_text(value):
    return format(value if value else Decimal(0), ".6f")


@dataclass(frozen=True)
class Replay:
    balance: Decimal
    pending: int
    opening: Decimal | None
    effects: tuple


def _stored_conversion(amount, rate, rate_date, cutoff):
    if rate is None or rate <= 0 or rate_date is None or rate_date > cutoff:
        return None
    with localcontext() as context:
        context.prec = 50
        result = (amount * rate).quantize(Decimal("0.000001"))
    return result if result.copy_abs() < Decimal(10)**14 else None


def replay(account, rows, *, include_adjustments=True, as_of_date=None, resolve_stored_rates=True):
    opening = account.opening_balance if account.currency == "CNY" else account.opening_cny_amount
    cutoff = as_of_date or date.today()
    if opening is None and resolve_stored_rates:
        opening = _stored_conversion(account.opening_balance, account.opening_exchange_rate,
                                     account.opening_rate_date, cutoff)
    balance = opening if opening is not None else Decimal(0)
    pending = int(opening is None)
    effects = []
    for row in rows:
        if (row.deleted_at is not None or (row.kind == "adjustment" and not include_adjustments)
                or (as_of_date is not None and row.occurred_on > as_of_date)):
            continue
        legs = []
        if row.kind == "transfer":
            if row.from_account_id == account.id:
                legs.append(("from", -1))
            if row.to_account_id == account.id:
                legs.append(("to", 1))
        elif row.account_id == account.id:
            if row.kind == "adjustment":
                legs.append(("adjustment", 1))
            elif row.kind in {"income", "expense"}:
                positive = row.kind == ("expense" if account.kind == "liability" else "income")
                legs.append(("account", 1 if positive else -1))
        if not legs:
            continue
        value = row.cny_amount if row.cny_amount is not None else (row.amount if row.currency == "CNY" else None)
        if value is None and resolve_stored_rates:
            value = _stored_conversion(row.amount, row.exchange_rate, row.exchange_rate_date, cutoff)
        if value is None:
            pending += 1
        for role, sign in legs:
            delta = value * sign if value is not None else None
            if delta is not None:
                balance += delta
            effects.append((row.id, role, row.occurred_on.isoformat(), decimal_text(delta) if delta is not None else None))
    return Replay(balance, pending, opening, tuple(sorted(effects)))


def account_balance(account, rows, *, include_adjustments=True, as_of_date=None, resolve_stored_rates=True):
    result = replay(account, rows, include_adjustments=include_adjustments, as_of_date=as_of_date,
                    resolve_stored_rates=resolve_stored_rates)
    return result.balance, result.pending
