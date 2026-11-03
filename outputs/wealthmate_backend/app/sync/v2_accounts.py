from datetime import datetime, timezone
from decimal import InvalidOperation
from sqlalchemy import select
from ..assets.schemas import AccountIn, AccountPatch
from ..assets.service import save_account
from ..assets.names import available_account_name
from ..assets.domain import json_value
from ..models import Account, AccountMutationAudit
from .preferences import next_version, clear_inactive_default
from .v2_errors import Rejected, VersionConflict, validate, clean_payload, base_version, check_version

FINANCIAL = {"opening_balance", "opening_cny_amount", "opening_exchange_rate", "opening_rate_date",
             "opening_rate_source", "currency", "kind"}


def _canonical(value):
    if isinstance(value, datetime):
        return value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc)
    return value


def _values(op, existing, source=None):
    if source is None:
        data = clean_payload(op, AccountIn.model_fields, {"type": "kind"})
    else:
        data = {key: value for key, value in source.items() if key in AccountIn.model_fields and key != "id"}
        if "type" in source and "kind" not in data:
            data["kind"] = source["type"]
    flag = data.pop("is_default_payment", None)
    if source is None and flag is not None and flag != (existing.is_default_payment if existing else False):
        raise Rejected("read_only_field", "Use user_preferences to select the default account", "is_default_payment")
    for field in ("name", "note"):
        if isinstance(data.get(field), str):
            data[field] = data[field].strip()
    if isinstance(data.get("currency"), str):
        data["currency"] = data["currency"].upper()
    return validate(AccountIn if existing is None and source is None else AccountPatch, data)


def apply_account(db, user, op, existing):
    expected = base_version(op)
    if op.type == "delete":
        check_version(existing, op)
        if existing is not None:
            save_account(db, user, {"id": op.entity_id}, deleted=True, server_version=next_version(user))
            db.flush()
            clear_inactive_default(db, user, existing)
        return existing, "applied", [], []
    if existing is not None and existing.deleted_at is not None:
        raise Rejected("entity_deleted", "A tombstone cannot be resurrected")
    desired = _values(op, existing)
    field_conflicts = []
    status = "applied"
    if existing is not None and op.base is not None:
        if expected is not None and expected > existing.server_version:
            raise VersionConflict(existing)
        base = _values(op, existing, op.base)
        financial_intent = any(field in FINANCIAL and field in base and _canonical(value) != _canonical(base[field])
                               for field, value in desired.items())
        if financial_intent:
            for field in FINANCIAL & base.keys():
                current = _canonical(getattr(existing, field))
                if current != _canonical(base[field]) and (field not in desired or current != _canonical(desired[field])):
                    raise Rejected("financial_conflict", "Financial framework changed since the baseline", field)
        changes = {}
        for field, client in desired.items():
            if field not in base:
                raise Rejected("base_field_missing", "Baseline is missing a submitted field", field)
            current = getattr(existing, field)
            old = base[field]
            if _canonical(client) == _canonical(old):
                continue
            if _canonical(current) != _canonical(old) and _canonical(current) != _canonical(client):
                if field in FINANCIAL:
                    raise Rejected("financial_conflict", "Financial fields cannot be merged across competing changes", field)
                field_conflicts.append(json_value(dict(field=field, base=old, client=client, server=current)))
            elif _canonical(current) != _canonical(client):
                changes[field] = client
        desired = changes
        status = "merged"
    else:
        # A stale financial proposal is a business rejection, per the V2 contract.
        if existing is not None and expected is not None and expected != existing.server_version:
            changed_financial = [f for f in desired if f in FINANCIAL and desired[f] != getattr(existing, f)]
            if changed_financial:
                raise Rejected("financial_conflict", "Financial proposal uses a stale baseline", sorted(changed_financial)[0])
        check_version(existing, op)
    if "name" in desired:
        occupied = set(db.scalars(select(Account.normalized_name).where(
            Account.user_id == user.id, Account.deleted_at.is_(None), Account.id != op.entity_id)).all())
        safe = available_account_name(desired["name"], op.entity_id, occupied)
        if safe != desired["name"]:
            db.add(AccountMutationAudit(user_id=user.id, account_id=op.entity_id,
                client_op_id=op.client_op_id, event_kind="v2_name_repaired",
                before_json={"name": desired["name"]}, after_json={"name": safe}, reason="Duplicate normalized account name"))
            desired["name"] = safe
    applied = [key for key, value in desired.items() if existing is None or _canonical(getattr(existing, key)) != _canonical(value)]
    if existing is None or applied:
        try:
            row = save_account(db, user, {"id": op.entity_id, **desired}, server_version=next_version(user))
        except InvalidOperation:
            raise Rejected("invalid_amount", "Converted opening amount exceeds storage precision") from None
        # Cached FX can overflow even when the submitted opening fits storage.
        validate(AccountPatch, {field: getattr(row, field) for field in FINANCIAL})
        db.flush()
        clear_inactive_default(db, user, row)
    else:
        row = existing
    return row, status, applied, field_conflicts
