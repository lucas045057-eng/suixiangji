"""Preflight all v3 sections and cross-record invariants before any restore writes."""
import math
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import HTTPException

from ..assets.schemas import AccountPatch
from ..models import Account, Transaction, Category, Budget, SyncOperation
from ..sync.v2_accounts import FINANCIAL
from ..sync.v2_errors import validate as validate_values, Rejected
from . import v3_schemas as schemas


def invalid(detail, field=None):
    raise HTTPException(422, detail=dict(code="invalid_backup", detail=detail, field=field))


def conflict(detail, row=None):
    raise HTTPException(409, detail=dict(code="version_conflict", detail=detail, authoritative_row=row))


def finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        invalid("Nonfinite JSON value")
    if isinstance(value, dict):
        for item in value.values():
            finite(item)
    elif isinstance(value, list):
        for item in value:
            finite(item)


def typed(model, data):
    try:
        values = validate_values(model, data)
    except Rejected as exc:
        invalid(exc.detail, exc.field)
    for key, value in values.items():
        if isinstance(value, str):
            if "\x00" in value:
                invalid("NUL character in text column", key)
            try:
                value.encode("utf-8")
            except UnicodeEncodeError:
                invalid("Invalid Unicode text", key)
    return model(**values).model_dump()


def _aliases(raw, transaction=False):
    data = {k: v for k, v in raw.items() if k not in {"server_version", "updated_at"}}
    aliases = {"type": "kind"}
    if transaction:
        aliases.update(date="occurred_on", original_amount="amount", original_currency="currency")
    for alias, key in aliases.items():
        if alias in data:
            value = data.pop(alias)
            if key in data and data[key] != value:
                invalid("Conflicting aliases", key)
            data[key] = value
    if isinstance(data.get("currency"), str):
        data["currency"] = data["currency"].upper()
    return data


def guard_existing_finances(payload, db, user):
    """Old files cannot overwrite accepted V2 financial anchors or tombstones."""
    adjusted = {row[0] for row in db.query(Transaction.account_id).filter_by(user_id=user.id, kind="adjustment").all()}
    for raw in payload.transactions:
        existing = db.get(Transaction, raw["id"], populate_existing=True)
        if payload.schema_version != 3 and existing is not None and existing.user_id == user.id and existing.kind == "adjustment":
            conflict("Legacy backups cannot overwrite an accepted adjustment")
    for raw in payload.accounts:
        existing = db.get(Account, raw["id"], populate_existing=True)
        if existing is None or existing.user_id != user.id:
            continue
        if existing.deleted_at is not None and raw.get("deleted_at") is None:
            conflict("A backup cannot resurrect an account tombstone")
        if user.min_client_protocol < 2 and existing.id not in adjusted:
            continue
        try:
            data = validate_values(AccountPatch, _aliases(raw))
        except Rejected as exc:
            invalid(exc.detail, exc.field)
        if "currency" in data:
            data["currency"] = data["currency"].upper()
        for key in FINANCIAL & data.keys():
            value = data[key]
            current = getattr(existing, key)
            if key in {"opening_balance", "opening_cny_amount", "opening_exchange_rate"} and value is not None:
                value = Decimal(str(value))
            if key == "opening_rate_date" and isinstance(value, str):
                from datetime import date
                value = date.fromisoformat(value)
            if current != value:
                from ..assets.service import account_json
                conflict("Backup conflicts with an existing financial anchor", account_json(existing))


def _unique(records, key, section):
    keys = set()
    for row in records:
        value = key(row)
        if value in keys:
            invalid("Duplicate record in "+section)
        keys.add(value)


def _adjustment_metadata(row):
    meta = row["adjustment_meta"]
    if meta.get("effective_on") != row["occurred_on"].isoformat():
        invalid("Adjustment metadata date differs from occurred_on", "adjustment_meta")
    try:
        if not isinstance(meta.get("captured_at"), str):
            raise ValueError()
        datetime.fromisoformat(meta["captured_at"].replace("Z", "+00:00"))
    except ValueError:
        invalid("Invalid adjustment captured_at", "adjustment_meta")
    if row.get("reverses_transaction_id"):
        if meta.get("reason") != "reversal":
            invalid("Invalid reversal metadata", "adjustment_meta")
    else:
        if meta.get("reason") != "balance_calibration":
            invalid("Invalid calibration metadata", "adjustment_meta")
        try:
            from ..assets.schemas import CalibrationIn
            values = typed(CalibrationIn, dict(client_op_id=row["client_op_id"], adjustment_id=row["id"],
                target_cny=meta.get("target_cny"), expected_current_cny=meta.get("basis_balance_cny"),
                effective_on=row["occurred_on"]))
            if values["target_cny"] - values["expected_current_cny"] != row["amount"]:
                invalid("Calibration metadata delta does not match amount", "adjustment_meta")
        except (ValueError, TypeError):
            invalid("Invalid calibration monetary metadata", "adjustment_meta")


def _receipt(row, db, user, source_version):
    if row["server_version"] > source_version:
        invalid("Receipt version exceeds source watermark", "sync_operations")
    outcome = row.get("result_json")
    rejected = bool(outcome and "rejected" in outcome)
    models = dict(accounts=Account, categories=Category, transactions=Transaction, budgets=Budget)
    model = models.get(row["entity"])
    if model:
        current = db.get(model, row["entity_id"], populate_existing=True)
        if current is not None and current.user_id != user.id and not rejected:
            invalid("Receipt refers to an unavailable resource", "sync_operations")
    elif row["entity"] == "user_preferences" and row["entity_id"] != "self":
        invalid("Invalid preference receipt ID")
    if row["protocol_version"] == 2:
        if not row.get("request_hash") or not outcome or set(outcome) - {"result", "rejected", "conflict"}:
            invalid("V2 receipt requires a stable request hash and outcome", "sync_operations")
        if ("rejected" in outcome) + ("conflict" in outcome) > 1:
            invalid("Receipt has multiple outcomes")
        if "result" not in outcome and "conflict" not in outcome:
            invalid("Receipt is missing its outcome")
    if outcome:
        for group, item in outcome.items():
            if not isinstance(item, dict) or any(item.get(k) != v for k, v in {
                "op_id": row["client_op_id"], "entity": row["entity"], "id": row["entity_id"]}.items()):
                invalid("Receipt outcome identity mismatch", "sync_operations")
            if group == "result" and item.get("status") not in {"applied", "merged", "rejected", "conflict"}:
                invalid("Unknown receipt result status")
            for key in ("row", "authoritative_row"):
                snapshot = item.get(key)
                if rejected and snapshot is not None:
                    invalid("A rejected receipt must not contain a resource row")
                if snapshot is not None and (not isinstance(snapshot, dict) or snapshot.get("id") != row["entity_id"]):
                    invalid("Receipt row identity mismatch")
                if snapshot and snapshot.get("user_id", user.id) != user.id:
                    invalid("Receipt row belongs to another user")
                if snapshot:
                    for field, target in [("default_account_id", Account), ("account_id", Account),
                                          ("from_account_id", Account), ("to_account_id", Account), ("category_id", Category)]:
                        reference = snapshot.get(field)
                        if reference:
                            if not isinstance(reference, str):
                                invalid("Invalid reference in receipt row", field)
                            owned = db.get(target, reference, populate_existing=True)
                            if owned is not None and owned.user_id != user.id:
                                invalid("Receipt row references another user", field)
        result = outcome.get("result", {})
        expected = "rejected" if "rejected" in outcome else "conflict" if "conflict" in outcome else None
        if expected is not None and result and result.get("status") != expected:
            invalid("Receipt grouped outcome differs from result status")
        if not expected and result.get("status") not in {"applied", "merged"}:
            invalid("Incomplete grouped receipt outcome")


def precheck(payload, db, user):
    finite(payload.model_dump(mode="json"))
    if payload.protocol_metadata is None or payload.source_server_version is None:
        invalid("V3 requires protocol_metadata and source_server_version")
    if payload.source_server_version > schemas.MAX_VERSION:
        invalid("Source watermark exceeds storage capacity")
    sections = dict(accounts=[], categories=[], transactions=[], budgets=[])
    for name, model in [("accounts", schemas.AccountRecord), ("categories", schemas.CategoryRecord),
                        ("budgets", schemas.BudgetRecord)]:
        for raw in getattr(payload, name):
            sections[name].append(typed(model, _aliases(raw)))
    for raw in payload.transactions:
        data = _aliases(raw, transaction=True)
        adjustment = data.get("kind") == "adjustment"
        row = typed(schemas.AdjustmentRecord if adjustment else schemas.TransactionRecord, data)
        if adjustment:
            _adjustment_metadata(row)
        elif row.get("cny_amount") is not None and row["cny_amount"] <= 0:
            invalid("Ordinary transactions require a positive CNY amount", "cny_amount")
        sections["transactions"].append(row)
    for name, model in [("user_preferences", schemas.PreferenceRecord), ("sync_operations", schemas.ReceiptRecord),
                        ("exchange_rates", schemas.RateRecord), ("net_worth_snapshots", schemas.NetWorthRecord),
                        ("account_mutation_audits", schemas.AuditRecord)]:
        sections[name] = [typed(model, raw) for raw in getattr(payload, name)]
    sections["protocol_metadata"] = typed(schemas.ProtocolRecord, payload.protocol_metadata)
    for name in ("accounts", "categories", "transactions", "budgets"):
        _unique(sections[name], lambda row: row["id"], name)
    _unique(sections["sync_operations"], lambda row: row["client_op_id"], "sync_operations")
    _unique(sections["net_worth_snapshots"], lambda row: row["month"], "net_worth_snapshots")
    _unique(sections["exchange_rates"], lambda row: (row["base_currency"], row["quote_currency"], row["rate_date"], row["source"]), "exchange_rates")
    _unique(sections["account_mutation_audits"], lambda row: (row["client_op_id"], row["event_kind"]), "account_mutation_audits")
    for row in sections["sync_operations"]:
        _receipt(row, db, user, payload.source_server_version)
    for row in sections["user_preferences"]:
        if row["server_version"] > payload.source_server_version:
            invalid("Preference version exceeds source watermark")
    # Validate the final merged graph, including already stored reversal rows.
    accounts = {row.id: row for row in db.query(Account).filter_by(user_id=user.id).all()}
    incoming_accounts = {row["id"]: row for row in sections["accounts"]}
    transactions = {row.id: {column.name: getattr(row, column.name) for column in Transaction.__table__.columns}
                    for row in db.query(Transaction).filter_by(user_id=user.id).all()}
    transactions.update({row["id"]: row for row in sections["transactions"]})
    reversals = set()
    for row in transactions.values():
        if row["kind"] != "adjustment":
            continue
        account_id = row["account_id"]
        if account_id not in accounts and account_id not in incoming_accounts:
            invalid("Adjustment account is unavailable", "account_id")
        original_id = row.get("reverses_transaction_id")
        if original_id:
            original = transactions.get(original_id)
            if (original is None or original["kind"] != "adjustment" or original.get("reverses_transaction_id")
                    or original["account_id"] != account_id or row["amount"] != -original["amount"]
                    or row["occurred_on"] < original["occurred_on"] or original_id in reversals):
                invalid("Invalid, dangling or duplicate reversal chain", "reverses_transaction_id")
            reversals.add(original_id)
    for row in sections["transactions"]:
        existing = db.get(Transaction, row["id"], populate_existing=True)
        if existing is not None and existing.user_id == user.id and (existing.kind == "adjustment" or row["kind"] == "adjustment"):
            if any(getattr(existing, key) != value for key, value in row.items()):
                conflict("An accepted adjustment is immutable")
    for row in sections["net_worth_snapshots"]:
        assets, debts, worth = (row.get(k) for k in ("total_assets_cny", "total_liabilities_cny", "net_worth_cny"))
        if assets is not None and debts is not None and worth is not None and assets-debts != worth:
            invalid("Inconsistent net worth snapshot totals")
    return payload.model_copy(update=sections)
