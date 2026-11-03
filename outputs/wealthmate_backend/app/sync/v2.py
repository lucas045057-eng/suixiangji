"""Header-selected V2: durable per-operation outcomes under one user lock."""
import hashlib
import json
from datetime import datetime, timezone
from decimal import InvalidOperation
from fastapi import HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError
from ..assets.service import account_json
from ..budget.schemas import BudgetIn
from ..budget.service import save_budget, budget_json
from ..core.financial_lock import lock_current_user
from ..core.protocol import enforce_sync_floor
from ..ledger.schemas import TransactionIn, CategoryIn
from ..ledger.service import save_transaction, normalise_transaction_payload, attach_latest_rate, transaction_json, save_category, category_json
from ..models import Account, Budget, Category, SyncOperation, Transaction, UserPreference
from .preferences import preference_json, set_preference, next_version
from .v2_accounts import apply_account
from .v2_errors import Rejected, VersionConflict, validate, clean_payload, check_version, base_version, finite_json

MODELS = {"accounts": Account, "transactions": Transaction, "categories": Category,
          "budgets": Budget, "user_preferences": UserPreference}
SERIALIZE = {"accounts": account_json, "transactions": transaction_json, "categories": category_json,
             "budgets": budget_json, "user_preferences": preference_json}


class PreferenceIn(BaseModel):
    default_account_id: str | None = Field(default=None, min_length=1, max_length=64)


class CategoryValues(CategoryIn):
    active: bool = True


def _owned(db, user, op):
    if op.entity not in MODELS:
        raise Rejected("unsupported_entity", "Unsupported sync entity")
    if op.entity == "user_preferences":
        if op.entity_id != "self":
            raise Rejected("invalid_preference_id", "Preferences use the singleton ID self", "entity_id")
        return db.get(UserPreference, user.id, populate_existing=True)
    row = db.get(MODELS[op.entity], op.entity_id, populate_existing=True)
    if row is not None and row.user_id != user.id:
        raise Rejected("not_found", "Resource is unavailable")
    return row


def _references(op):
    if op.entity == "transactions":
        return [("accounts", op.payload.get(k)) for k in ("account_id", "from_account_id", "to_account_id")] + [("categories", op.payload.get("category_id"))]
    if op.entity == "budgets":
        return [("categories", op.payload.get("category_id"))]
    if op.entity == "user_preferences":
        return [("accounts", op.payload.get("default_account_id"))]
    return []


def _active_references(db, user, data):
    for field, model in [("account_id", Account), ("from_account_id", Account), ("to_account_id", Account), ("category_id", Category)]:
        identifier = data.get(field)
        if identifier:
            row = db.get(model, identifier, populate_existing=True)
            if row is None or row.user_id != user.id:
                raise Rejected("invalid_reference", "Reference is unavailable", field)
            if (model is Account and (row.deleted_at is not None or row.archived_at is not None)) or (model is Category and not row.active):
                raise Rejected("inactive_reference", "Reference is inactive", field)


def _apply(db, user, op, existing):
    base_version(op)
    if op.entity == "accounts":
        return apply_account(db, user, op, existing)
    if op.entity == "user_preferences":
        data = validate(PreferenceIn, clean_payload(op, PreferenceIn.model_fields))
        check_version(existing, op)
        default = None if op.type == "delete" else data.get("default_account_id", existing.default_account_id if existing else None)
        row = set_preference(db, user, default)
        return row, "applied", list(data), []
    if existing is not None and op.entity == "transactions" and existing.kind == "adjustment":
        raise Rejected("immutable_adjustment", "Use the dedicated reversal endpoint")
    if op.type == "delete":
        check_version(existing, op)
        if existing is not None:
            if op.entity == "categories":
                existing.active = False
            elif op.entity in {"transactions", "budgets"}:
                existing.deleted_at = datetime.now(timezone.utc)
                if op.entity == "budgets":
                    existing.active = False
            existing.server_version = next_version(user)
        return existing, "applied", [], []
    if existing is not None and ((op.entity in {"transactions", "budgets"} and existing.deleted_at is not None)):
        raise Rejected("entity_deleted", "A tombstone cannot be resurrected")
    if op.entity == "categories":
        data = clean_payload(op, CategoryValues.model_fields, {"type": "kind"})
        candidate = {f: getattr(existing, f) for f in ("name", "kind", "active")} if existing else {}
        candidate.update(data)
        candidate = validate(CategoryValues, candidate)
        check_version(existing, op)
        row = save_category(db, user, {"id": op.entity_id, **candidate}, server_version=next_version(user), active=candidate.get("active", True))
    elif op.entity == "budgets":
        data = clean_payload(op, BudgetIn.model_fields)
        candidate = {f: getattr(existing, f) for f in ("month", "category_id", "limit", "active")} if existing else {}
        candidate.update(data)
        candidate = validate(BudgetIn, candidate)
        check_version(existing, op)
        row = save_budget(db, user, {"id": op.entity_id, **candidate}, server_version=next_version(user))
    else:
        data = clean_payload(op, TransactionIn.model_fields, {"type": "kind", "date": "occurred_on", "original_amount": "amount", "original_currency": "currency"})
        candidate = {f: getattr(existing, f) for f in TransactionIn.model_fields if f not in {"id", "client_op_id"}} if existing else {}
        candidate.update(data, id=op.entity_id, client_op_id=op.client_op_id)
        candidate = validate(TransactionIn, candidate)
        check_version(existing, op)
        _active_references(db, user, candidate)
        try:
            normalized = normalise_transaction_payload(attach_latest_rate(db, candidate), entity_id=op.entity_id, client_op_id=op.client_op_id)
        except InvalidOperation:
            raise Rejected("invalid_amount", "Converted amount exceeds storage precision") from None
        validate(TransactionIn, normalized)
        if existing is not None and not (set(data) & {"amount", "currency", "cny_amount", "exchange_rate", "exchange_rate_date", "exchange_rate_source"}):
            for field in ("amount", "cny_amount", "exchange_rate", "exchange_rate_date", "exchange_rate_source", "conversion_status"):
                normalized[field] = getattr(existing, field)
        row = save_transaction(db, user, normalized, server_version=next_version(user))
    return row, "applied", list(data), []


def _identity(op):
    return dict(op_id=op.client_op_id, entity=op.entity, id=op.entity_id)


def _complete_result(op, outcome):
    if "conflict" in outcome and "result" not in outcome:
        conflict = outcome["conflict"]
        return {**outcome, "result": {**_identity(op), "status": "conflict",
            "reason": conflict["reason"], "row": conflict["authoritative_row"]}}
    return outcome


def _rejected(op, exc):
    detail = {**_identity(op), "code": exc.code, "detail": exc.detail}
    if exc.field is not None:
        detail["field"] = exc.field
    return dict(result={**_identity(op), "status": "rejected"}, rejected=detail)


def _http_rejection(exc):
    if isinstance(exc.detail, dict):
        return Rejected(exc.detail.get("code", "validation_error"), str(exc.detail.get("message", "Invalid operation")))
    codes = {404: "not_found", 409: "business_conflict", 422: "invalid_field", 403: "forbidden"}
    return Rejected(codes.get(exc.status_code, "validation_error"), str(exc.detail))


def _known_integrity(exc):
    name = getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
    if name in {"uq_accounts_user_normalized_name", "uq_budget_user_month_category", "uq_transaction_client_op", "uq_transaction_reversal"}:
        return True
    message = str(exc.orig)
    return message.startswith("UNIQUE constraint failed:") and any(t in message for t in ("accounts.user_id", "budgets.user_id", "transactions.user_id"))


def push(payload, db, user):
    results, rejected, conflicts = {}, {}, {}
    blocked = set()
    try:
        user = lock_current_user(db, user.id, verified_auth_version=user.auth_version or 0)
        enforce_sync_floor(user, 2)
        priorities = {"accounts": 0, "categories": 0, "transactions": 1, "budgets": 1, "user_preferences": 2}
        ordered = sorted(payload.operations, key=lambda op: priorities.get(op.entity, 3))
        # sqlite3 legacy transaction mode does not BEGIN on SELECT or SAVEPOINT.
        if db.get_bind().dialect.name == "sqlite":
            connection = db.connection()
            if not connection.connection.driver_connection.in_transaction:
                connection.exec_driver_sql("BEGIN")
        for op in ordered:
            request_hash = hashlib.sha256(json.dumps(op.model_dump(mode="json"), ensure_ascii=True,
                sort_keys=True, separators=(",", ":"), allow_nan=True).encode()).hexdigest()
            previous = db.query(SyncOperation).filter_by(user_id=user.id, client_op_id=op.client_op_id).first()
            if previous is not None:
                if previous.protocol_version == 2 and previous.request_hash == request_hash and previous.result_json:
                    outcome = previous.result_json
                else:
                    outcome = _rejected(op, Rejected("operation_mismatch", "Operation ID already used with different contents or protocol"))
            else:
                try:
                    with db.begin_nested():
                        finite_json(op.model_dump(mode="python"))
                        existing = _owned(db, user, op)
                        if any((entity, identifier) in blocked for entity, identifier in _references(op) if isinstance(identifier, str)):
                            raise Rejected("dependency_rejected", "A referenced operation was not applied")
                        row, status, fields, field_conflicts = _apply(db, user, op, existing)
                        db.flush()
                        result = {**_identity(op), "status": status, "fields_applied": fields,
                                  "row": SERIALIZE[op.entity](row) if row is not None else None}
                        if field_conflicts:
                            result["field_conflicts"] = field_conflicts
                        outcome = dict(result=result)
                except Rejected as exc:
                    outcome = _rejected(op, exc)
                except VersionConflict as exc:
                    outcome = dict(conflict={**_identity(op), "reason": "version_conflict",
                        "authoritative_row": SERIALIZE[op.entity](exc.row) if exc.row is not None else None})
                except HTTPException as exc:
                    if exc.status_code not in {403, 404, 409, 422}:
                        raise
                    if isinstance(exc.detail, dict) and exc.detail.get("code") == "balance_changed":
                        outcome = dict(conflict={**_identity(op), "reason": "balance_changed",
                            "authoritative_row": SERIALIZE[op.entity](existing) if existing else None})
                    else:
                        outcome = _rejected(op, _http_rejection(exc))
                except IntegrityError as exc:
                    if not _known_integrity(exc):
                        raise
                    outcome = _rejected(op, Rejected("duplicate_key", "Operation violates a business uniqueness constraint"))
                outcome = _complete_result(op, outcome)
                # Outcome receipts share the outer transaction. Unknown failures remain fatal.
                db.add(SyncOperation(user_id=user.id, client_op_id=op.client_op_id, entity=op.entity,
                    entity_id=op.entity_id, server_version=user.sync_version, protocol_version=2,
                    request_hash=request_hash, result_json=outcome))
                db.flush()
            outcome = _complete_result(op, outcome)
            if "result" in outcome:
                results[op.client_op_id] = outcome["result"]
            if "rejected" in outcome:
                rejected[op.client_op_id] = outcome["rejected"]
            if "conflict" in outcome:
                conflicts[op.client_op_id] = outcome["conflict"]
            if "rejected" in outcome or "conflict" in outcome:
                blocked.add((op.entity, op.entity_id))
            else:
                blocked.discard((op.entity, op.entity_id))
        db.commit()
    except BaseException:
        db.rollback()
        raise
    return dict(server_version=user.sync_version,
        results=[results[o.client_op_id] for o in payload.operations if o.client_op_id in results],
        rejected=[rejected[o.client_op_id] for o in payload.operations if o.client_op_id in rejected],
        conflicts=[conflicts[o.client_op_id] for o in payload.operations if o.client_op_id in conflicts])


def pull(since_version, db, user):
    from .service import pull as common_pull
    result = common_pull(since_version, db, user, include_adjustments=True, protocol=2)
    watermark = result["server_version"]
    rows = db.query(UserPreference).filter(UserPreference.user_id == user.id,
        UserPreference.server_version > since_version, UserPreference.server_version <= watermark).populate_existing().all()
    result["preferences"] = [preference_json(row) for row in rows]
    return result
