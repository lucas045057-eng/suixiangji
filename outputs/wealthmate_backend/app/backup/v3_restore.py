"""Atomic, tenant-scoped v3 restore; no per-record partial commits."""
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import HTTPException

from ..assets.service import save_account
from ..core.financial_lock import lock_current_user
from ..core.protocol import enforce_sync_floor
from ..models import (Account, Transaction, SyncOperation, UserPreference,
    UserExchangeRate, NetWorthSnapshot, AccountMutationAudit)
from ..sync.preferences import set_preference
from ..sync.v2_errors import Rejected
from .v3_schemas import MAX_VERSION
from .v3_validate import finite, precheck, guard_existing_finances, invalid, conflict, typed


def _stamp(value):
    if value is not None and value.tzinfo is not None:
        return value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _same(existing, data):
    return all((_stamp(getattr(existing, key)) if isinstance(value, datetime) else getattr(existing, key))
               == (_stamp(value) if isinstance(value, datetime) else value) for key, value in data.items())


def _accounts(db, user, records):
    from .v3_schemas import AccountRecord
    for raw in records:
        user.sync_version += 1
        row = save_account(db, user, raw, server_version=user.sync_version)
        # Restore stored snapshots exactly, including explicit NULLs; never revalue from today's FX.
        for field in ("opening_cny_amount", "opening_exchange_rate", "opening_rate_date", "opening_rate_source"):
            if field in raw:
                setattr(row, field, raw[field])
        row.deleted_at = _stamp(raw.get("deleted_at"))
        typed(AccountRecord, {key: getattr(row, key) for key in AccountRecord.model_fields})
        db.flush()


def _transactions(db, user, records):
    from ..ledger.service import save_transaction
    ordered = sorted(records, key=lambda row: bool(row.get("reverses_transaction_id")))
    for raw in ordered:
        values = {key: value for key, value in raw.items() if key != "deleted_at"}
        if raw["kind"] == "adjustment":
            if db.get(Transaction, raw["id"], populate_existing=True) is not None:
                continue
            user.sync_version += 1
            db.add(Transaction(user_id=user.id, **values, server_version=user.sync_version))
        else:
            user.sync_version += 1
            row = save_transaction(db, user, values, deleted=raw.get("deleted_at") is not None,
                                   server_version=user.sync_version)
            row.deleted_at = _stamp(raw.get("deleted_at"))
        # No normalizer or latest-rate lookup: backups retain even explicit NULL snapshots.
        db.flush()


def _preference(db, user, records):
    preference = db.get(UserPreference, user.id, populate_existing=True)
    if records:
        default_id = records[0]["default_account_id"]
    elif preference is not None:
        default_id = preference.default_account_id
        account = db.get(Account, default_id, populate_existing=True) if default_id else None
        if account is not None and (account.deleted_at or account.archived_at or account.kind != "asset"):
            default_id = None
    else:
        return
    try:
        set_preference(db, user, default_id)
    except Rejected as exc:
        invalid(exc.detail, exc.field)


def _auxiliary(db, user, payload):
    for raw in payload.exchange_rates:
        key = {name: raw[name] for name in ("base_currency", "quote_currency", "rate_date", "source")}
        row = db.query(UserExchangeRate).filter_by(user_id=user.id, **key).first()
        values = {**raw, "fetched_at": _stamp(raw["fetched_at"])}
        if row is None:
            db.add(UserExchangeRate(user_id=user.id, **values))
        else:
            for name, value in values.items():
                setattr(row, name, value)
    for raw in payload.net_worth_snapshots:
        db.add(NetWorthSnapshot(user_id=user.id, **{**raw, "created_at": _stamp(raw["created_at"])}))
    for raw in payload.account_mutation_audits:
        current = db.query(AccountMutationAudit).filter_by(user_id=user.id,
            client_op_id=raw["client_op_id"], event_kind=raw["event_kind"]).first()
        account = db.get(Account, raw["account_id"], populate_existing=True)
        if account is not None and account.user_id != user.id:
            invalid("Audit references an unavailable resource")
        if current is None:
            db.add(AccountMutationAudit(user_id=user.id, **raw))
        elif not _same(current, raw):
            conflict("An existing mutation audit differs from the backup")
    for raw in payload.sync_operations:
        current = db.query(SyncOperation).filter_by(user_id=user.id, client_op_id=raw["client_op_id"]).first()
        if current is None:
            db.add(SyncOperation(user_id=user.id, **{**raw, "created_at": _stamp(raw["created_at"])}))
        elif not _same(current, raw):
            conflict("An existing operation receipt differs from the backup")
    db.flush()


def _verify_restored(db, user, payload):
    preference = db.get(UserPreference, user.id, populate_existing=True)
    if preference is not None:
        flagged = db.query(Account).filter_by(user_id=user.id, is_default_payment=True).all()
        expected = {preference.default_account_id} if preference.default_account_id else set()
        if {row.id for row in flagged} != expected:
            invalid("Restored preference projection is inconsistent")
    for raw in payload.transactions:
        if raw["kind"] != "adjustment":
            continue
        row = db.get(Transaction, raw["id"], populate_existing=True)
        if row is None or row.user_id != user.id or not _same(row, raw):
            invalid("Restored immutable adjustment differs from its backup")
        if row.reverses_transaction_id:
            original = db.get(Transaction, row.reverses_transaction_id, populate_existing=True)
            if (original is None or original.user_id != user.id or original.kind != "adjustment"
                    or original.reverses_transaction_id is not None or original.account_id != row.account_id
                    or original.amount != -row.amount or original.occurred_on > row.occurred_on):
                invalid("Restored reversal chain is inconsistent")


def restore_backup(payload, db, user, *, protocol=1):
    """Same restore_id: zero writes. New ID: reuse business rows, add one receipt.

    Mutable-row versions can advance for a new ID; accepted adjustments stay immutable.
    """
    from .service import (_validate_payload_limits, _content_hash, _precheck_records,
                          _apply_categories, _apply_budgets, _apply_profile, _invalidate_derived_data)
    _validate_payload_limits(payload)
    finite(payload.model_dump(mode="python"))
    if payload.owner_id != user.id:
        invalid("Backup does not belong to the current user", "owner_id")
    restore_id = payload.restore_id or str(uuid4())
    operation_id = "restore:"+restore_id
    if len(operation_id) > 128 or "\x00" in operation_id:
        invalid("Invalid restore_id", "restore_id")
    content_hash = _content_hash(payload)
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
        enforce_sync_floor(user, protocol)
        previous = db.query(SyncOperation).filter_by(user_id=user.id, client_op_id=operation_id).first()
        if previous is not None:
            if previous.entity != "backup_restore" or previous.entity_id != content_hash:
                raise HTTPException(409, detail=dict(code="operation_mismatch", detail="Restore ID already used"))
            return dict(restored=True, replayed=True, restore_id=restore_id, server_version=previous.server_version,
                accounts=0, categories=0, transactions=0, budgets=0, user_preferences=0,
                sync_operations=0, exchange_rates=0, net_worth_snapshots=0, account_mutation_audits=0)
        payload = precheck(payload, db, user)
        _precheck_records(payload, db, user)
        guard_existing_finances(payload, db, user)
        if any(row["client_op_id"] == operation_id for row in payload.sync_operations):
            conflict("Restore command ID collides with an imported receipt")
        minimum = payload.protocol_metadata["min_client_protocol"]
        if any(row["kind"] == "adjustment" for row in payload.transactions):
            minimum = max(minimum, 2)
        if protocol < minimum:
            raise HTTPException(426, detail=dict(code="upgrade_required", min_protocol=minimum))
        ceiling = max(user.sync_version, payload.source_server_version)
        capacity = (len(payload.accounts)+len(payload.categories)+len(payload.transactions)+len(payload.budgets)
                    +db.query(Account).filter_by(user_id=user.id).count()+len(payload.accounts)+2)
        if ceiling + capacity > MAX_VERSION:
            invalid("Restored data exceeds sync version capacity")
        user.sync_version = ceiling
        user.min_client_protocol = max(user.min_client_protocol, minimum)
        _accounts(db, user, payload.accounts)
        _apply_categories(db, user, payload.categories)
        _apply_budgets(db, user, payload.budgets)
        _transactions(db, user, payload.transactions)
        _apply_profile(user, payload)
        _preference(db, user, payload.user_preferences)
        _invalidate_derived_data(db, user.id)
        _auxiliary(db, user, payload)
        _verify_restored(db, user, payload)
        user.sync_version += 1
        db.add(SyncOperation(user_id=user.id, client_op_id=operation_id, entity="backup_restore",
                            entity_id=content_hash, server_version=user.sync_version, request_hash=content_hash))
        db.flush()
        result = dict(restored=True, replayed=False, restore_id=restore_id, server_version=user.sync_version,
            accounts=len(payload.accounts), categories=len(payload.categories), transactions=len(payload.transactions),
            budgets=len(payload.budgets), user_preferences=len(payload.user_preferences),
            sync_operations=len(payload.sync_operations), exchange_rates=len(payload.exchange_rates),
            net_worth_snapshots=len(payload.net_worth_snapshots), account_mutation_audits=len(payload.account_mutation_audits))
        db.commit()
        return result
    except BaseException:
        db.rollback()
        raise
