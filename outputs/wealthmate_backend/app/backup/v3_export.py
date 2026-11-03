"""Lock-consistent v3 export with an explicit, replay-safe export event."""
from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import or_, and_

from ..config import get_settings
from ..core.financial_lock import lock_current_user
from ..core.protocol import enforce_sync_floor
from ..models import (Account, Category, Transaction, Budget, UserPreference,
    SyncOperation, NetWorthSnapshot, ExchangeRate, UserExchangeRate, AccountMutationAudit)
from ..sync.preferences import preference_json
from .v3_schemas import MAX_VERSION


def _rates(db, user_id, accounts, transactions):
    from .service import _decimal_text, _iso
    keys = {(a.currency, "CNY", a.opening_rate_date, a.opening_rate_source)
            for a in accounts if a.currency != "CNY" and a.opening_rate_date and a.opening_rate_source}
    keys.update((t.currency, "CNY", t.exchange_rate_date, t.exchange_rate_source)
                for t in transactions if t.currency != "CNY" and t.exchange_rate_date and t.exchange_rate_source)
    rows = []
    # Exact snapshot keys avoid exporting unrelated public cache history.
    ordered = sorted(keys)
    for offset in range(0, len(ordered), 100):
        predicates = [and_(ExchangeRate.base_currency == base, ExchangeRate.quote_currency == quote,
                          ExchangeRate.rate_date == day, ExchangeRate.source == source)
                      for base, quote, day, source in ordered[offset:offset+100]]
        rows.extend(db.query(ExchangeRate).filter(or_(*predicates)).all())
    rates = {(row.base_currency, row.quote_currency, row.rate_date, row.source): row for row in rows}
    for row in db.query(UserExchangeRate).filter_by(user_id=user_id).all():
        rates[row.base_currency, row.quote_currency, row.rate_date, row.source] = row
    return [dict(base_currency=row.base_currency, quote_currency=row.quote_currency,
                 rate=_decimal_text(row.rate), rate_date=_iso(row.rate_date), source=row.source,
                 fetched_at=_iso(row.fetched_at)) for _, row in sorted(rates.items())]


def export_backup(db, user, *, protocol=1):
    from .service import (_backup_account, _backup_category, _backup_transaction, _backup_budget,
                          _decimal_text, _iso, _validate_payload_limits)
    from .schemas import RestoreIn
    from fastapi import HTTPException
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
        enforce_sync_floor(user, protocol)
        if user.sync_version >= MAX_VERSION:
            raise HTTPException(422, detail="Sync version capacity exhausted")
        user.sync_version += 1
        export_id = str(uuid4())
        db.add(SyncOperation(user_id=user.id, client_op_id="backup-export:"+export_id,
                            entity="backup_export", entity_id=export_id, server_version=user.sync_version))
        db.flush()
        def owned(model):
            return db.query(model).filter(model.user_id == user.id).order_by(model.id).populate_existing().all()
        accounts, categories, transactions, budgets = [owned(m) for m in (Account, Category, Transaction, Budget)]
        preference = db.get(UserPreference, user.id, populate_existing=True)
        result = dict(kind="suixiangji.backup", schema_version=3,
            exported_at=datetime.now(timezone.utc).isoformat(), owner_id=user.id,
            source_server_version=user.sync_version,
            profile=dict(display_name=user.display_name or user.username, quick_memories=user.quick_memories or []),
            accounts=[_backup_account(row) for row in accounts],
            categories=[_backup_category(row) for row in categories],
            transactions=[_backup_transaction(row) for row in transactions],
            budgets=[_backup_budget(row) for row in budgets],
            user_preferences=[preference_json(preference)] if preference else [],
            protocol_metadata=dict(sync_protocol=2,
                min_client_protocol=max(user.min_client_protocol, get_settings().min_client_protocol),
                financial_model="cny_adjustments_v1"),
            sync_operations=[dict(client_op_id=row.client_op_id, entity=row.entity, entity_id=row.entity_id,
                server_version=row.server_version, protocol_version=row.protocol_version,
                request_hash=row.request_hash, result_json=row.result_json, created_at=_iso(row.created_at))
                for row in owned(SyncOperation)],
            exchange_rates=_rates(db, user.id, accounts, transactions),
            net_worth_snapshots=[dict(month=row.month, total_assets_cny=_decimal_text(row.total_assets_cny),
                total_liabilities_cny=_decimal_text(row.total_liabilities_cny), net_worth_cny=_decimal_text(row.net_worth_cny),
                pending_conversion_count=row.pending_conversion_count, created_at=_iso(row.created_at))
                for row in owned(NetWorthSnapshot)],
            account_mutation_audits=[dict(account_id=row.account_id, client_op_id=row.client_op_id,
                event_kind=row.event_kind, before_json=row.before_json, after_json=row.after_json,
                reason=row.reason, created_at=_iso(row.created_at)) for row in owned(AccountMutationAudit)])
        _validate_payload_limits(RestoreIn(**result))
        db.commit()
        return result
    except BaseException:
        db.rollback()
        raise
