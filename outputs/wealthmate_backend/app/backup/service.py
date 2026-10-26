from __future__ import annotations

import hashlib
import json
import re
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Any, Iterable
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..assets.service import save_account
from ..budget.service import budget_with_same_key, save_budget
from ..ledger.service import (
    attach_latest_rate,
    normalise_transaction_payload,
    save_category,
    save_transaction,
)
from ..ledger.domain import date_value
from ..models import (
    Account,
    Budget,
    Category,
    MonthlyReport,
    NetWorthSnapshot,
    SyncOperation,
    Transaction,
    User,
)
from ..sync.service import _lock_current_user
from .schemas import RestoreIn


BACKUP_KIND = "suixiangji.backup"
BACKUP_SCHEMA_VERSION = 2
MAX_BACKUP_BYTES = 10 * 1024 * 1024
MAX_ACCOUNTS = 5_000
MAX_CATEGORIES = 5_000
MAX_BUDGETS = 5_000
MAX_TRANSACTIONS = 50_000
_MONTH_RE = re.compile(r"^\d{4}-(?:0[1-9]|1[0-2])$")
_DECIMAL_KEYS = {
    "amount",
    "original_amount",
    "cny_amount",
    "exchange_rate",
    "opening_balance",
    "opening_cny_amount",
    "opening_exchange_rate",
    "limit",
}
_VERSION_FIELDS = {"server_version", "updated_at"}
_ACCOUNT_KINDS = {
    "cash",
    "bank_card",
    "wechat",
    "alipay",
    "foreign",
    "fund_investment",
    "credit_card",
    "loan",
    "other",
}


def _decimal_text(value: Decimal | int | float | str | None) -> str | None:
    if value is None:
        return None
    try:
        decimal = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail="备份中的金额格式无效") from exc
    if not decimal.is_finite():
        raise HTTPException(status_code=422, detail="备份中的金额格式无效")
    return format(decimal, "f")


def _canonical_decimal_text(value: Any) -> str:
    try:
        decimal = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail="备份中的金额格式无效") from exc
    if not decimal.is_finite():
        raise HTTPException(status_code=422, detail="备份中的金额格式无效")
    if decimal == 0:
        return "0"
    return format(decimal.normalize(), "f")


def _iso(value: date | datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _backup_account(row: Account) -> dict[str, Any]:
    return {
        "id": row.id,
        "name": row.name,
        "note": row.note,
        "archived_at": _iso(row.archived_at),
        "type": row.kind,
        "kind": row.kind,
        "account_kind": row.account_kind,
        "currency": row.currency,
        "opening_balance": _decimal_text(row.opening_balance),
        "opening_cny_amount": _decimal_text(row.opening_cny_amount),
        "opening_exchange_rate": _decimal_text(row.opening_exchange_rate),
        "opening_rate_date": _iso(row.opening_rate_date),
        "opening_rate_source": row.opening_rate_source,
        "is_liquid": row.is_liquid,
        "is_default_payment": row.is_default_payment,
        "deleted_at": _iso(row.deleted_at),
    }


def _backup_category(row: Category) -> dict[str, Any]:
    return {
        "id": row.id,
        "name": row.name,
        "active": row.active,
        "type": row.kind,
        "kind": row.kind,
    }


def _backup_transaction(row: Transaction) -> dict[str, Any]:
    return {
        "id": row.id,
        "date": _iso(row.occurred_on),
        "occurred_on": _iso(row.occurred_on),
        "type": row.kind,
        "kind": row.kind,
        "amount": _decimal_text(row.amount),
        "currency": row.currency,
        "original_amount": _decimal_text(row.amount),
        "original_currency": row.currency,
        "cny_amount": _decimal_text(row.cny_amount),
        "exchange_rate": _decimal_text(row.exchange_rate),
        "exchange_rate_date": _iso(row.exchange_rate_date),
        "exchange_rate_source": row.exchange_rate_source,
        "conversion_status": row.conversion_status,
        "category_id": row.category_id,
        "category_name": row.category_name,
        "account_id": row.account_id,
        "from_account_id": row.from_account_id,
        "to_account_id": row.to_account_id,
        "occurred_at": row.occurred_at or f"{row.occurred_on.isoformat()}T00:00:00",
        "note": row.note,
        "client_op_id": row.client_op_id,
        "deleted_at": _iso(row.deleted_at),
    }


def _backup_budget(row: Budget) -> dict[str, Any]:
    return {
        "id": row.id,
        "month": row.month,
        "category_id": row.category_id,
        "limit": _decimal_text(row.limit),
        "active": row.active,
        "deleted_at": _iso(row.deleted_at),
    }


def export_backup(db: Session, user: User) -> dict[str, Any]:
    """Export one lock-consistent V2 snapshot without advancing the watermark."""
    started_transaction = db.in_transaction()
    if not started_transaction:
        db.begin()
    try:
        locked_user = _lock_current_user(
            db,
            user.id,
            verified_auth_version=user.auth_version or 0,
        )
        accounts = (
            db.query(Account)
            .filter(Account.user_id == locked_user.id)
            .order_by(Account.id.asc())
            .all()
        )
        categories = (
            db.query(Category)
            .filter(Category.user_id == locked_user.id)
            .order_by(Category.id.asc())
            .all()
        )
        transactions = (
            db.query(Transaction)
            .filter(Transaction.user_id == locked_user.id)
            .order_by(Transaction.id.asc())
            .all()
        )
        budgets = (
            db.query(Budget)
            .filter(Budget.user_id == locked_user.id)
            .order_by(Budget.id.asc())
            .all()
        )
        result = {
            "kind": BACKUP_KIND,
            "schema_version": BACKUP_SCHEMA_VERSION,
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "owner_id": locked_user.id,
            "source_server_version": locked_user.sync_version,
            "profile": {
                "display_name": locked_user.display_name or locked_user.username,
                "quick_memories": locked_user.quick_memories or [],
            },
            "accounts": [_backup_account(row) for row in accounts],
            "categories": [_backup_category(row) for row in categories],
            "transactions": [_backup_transaction(row) for row in transactions],
            "budgets": [_backup_budget(row) for row in budgets],
        }
        return result
    finally:
        if not started_transaction:
            db.rollback()


def _canonical_value(key: str | None, value: Any) -> Any:
    if key in _VERSION_FIELDS:
        return None
    if key in _DECIMAL_KEYS and value is not None:
        return _canonical_decimal_text(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {
            child_key: _canonical_value(child_key, child_value)
            for child_key, child_value in sorted(value.items())
            if child_key not in _VERSION_FIELDS
        }
    if isinstance(value, list):
        return [_canonical_value(None, item) for item in value]
    return value


def _canonical_record(value: dict[str, Any]) -> dict[str, Any]:
    return {
        key: _canonical_value(key, item)
        for key, item in sorted(value.items())
        if key not in _VERSION_FIELDS
    }


def _content_hash(payload: RestoreIn) -> str:
    profile = (
        payload.profile.model_dump(exclude_none=False)
        if payload.profile is not None
        else None
    )
    canonical = {
        "owner_id": payload.owner_id,
        "profile": _canonical_value("profile", profile),
        "accounts": sorted(
            (_canonical_record(item) for item in payload.accounts),
            key=lambda item: str(item.get("id", "")),
        ),
        "categories": sorted(
            (_canonical_record(item) for item in payload.categories),
            key=lambda item: str(item.get("id", "")),
        ),
        "transactions": sorted(
            (_canonical_record(item) for item in payload.transactions),
            key=lambda item: str(item.get("id", "")),
        ),
        "budgets": sorted(
            (_canonical_record(item) for item in payload.budgets),
            key=lambda item: str(item.get("id", "")),
        ),
    }
    encoded = json.dumps(
        canonical,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _payload_as_json(payload: RestoreIn) -> bytes:
    return json.dumps(
        payload.model_dump(mode="json"),
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _validate_id(value: Any, *, field: str, index: int) -> str:
    if not isinstance(value, str) or not value or len(value) > 64:
        raise HTTPException(
            status_code=422,
            detail=f"备份 {field}[{index}] 的 id 无效",
        )
    return value


def _validate_payload_limits(payload: RestoreIn) -> None:
    counts = (
        ("accounts", payload.accounts, MAX_ACCOUNTS),
        ("categories", payload.categories, MAX_CATEGORIES),
        ("transactions", payload.transactions, MAX_TRANSACTIONS),
        ("budgets", payload.budgets, MAX_BUDGETS),
    )
    for name, records, limit in counts:
        if len(records) > limit:
            raise HTTPException(status_code=413, detail=f"备份 {name} 数量超过上限")
        for index, record in enumerate(records):
            _validate_id(record.get("id"), field=name, index=index)
            for field in ("deleted_at", "archived_at"):
                if field in record and record[field] is not None:
                    _parse_timestamp(record[field], field=field, index=index)
    if len(_payload_as_json(payload)) > MAX_BACKUP_BYTES:
        raise HTTPException(status_code=413, detail="备份文件超过 10 MiB 上限")


def _parse_timestamp(value: Any, *, field: str, index: int) -> datetime:
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 时间格式无效")
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 时间格式无效") from exc


def _validate_decimal(value: Any, *, field: str, index: int, positive: bool = False) -> None:
    if value is None:
        return
    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 金额格式无效") from exc
    if not number.is_finite() or (positive and number <= 0):
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 金额格式无效")


def _validate_date(value: Any, *, field: str, index: int, required: bool = False) -> None:
    if value is None:
        if required:
            raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 日期无效")
        return
    if isinstance(value, datetime):
        return
    if isinstance(value, date):
        return
    if not isinstance(value, str):
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 日期无效")
    try:
        date.fromisoformat(value[:10])
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"备份 {field}[{index}] 日期无效") from exc


def _precheck_records(payload: RestoreIn, db: Session, user: User) -> None:
    records_by_name: Iterable[tuple[str, list[dict[str, Any]]]] = (
        ("accounts", payload.accounts),
        ("categories", payload.categories),
        ("transactions", payload.transactions),
        ("budgets", payload.budgets),
    )
    for name, records in records_by_name:
        ids: set[str] = set()
        for index, record in enumerate(records):
            identifier = _validate_id(record.get("id"), field=name, index=index)
            if identifier in ids:
                raise HTTPException(status_code=422, detail=f"备份 {name} 含重复 id")
            ids.add(identifier)

    # Reject IDs owned by another tenant before any entity is flushed. The
    # save_* helpers repeat this check as a defensive backstop during apply.
    for model, name, records in (
        (Account, "accounts", payload.accounts),
        (Category, "categories", payload.categories),
        (Budget, "budgets", payload.budgets),
        (Transaction, "transactions", payload.transactions),
    ):
        for index, record in enumerate(records):
            existing = db.get(model, record["id"])
            if existing is not None and existing.user_id != user.id:
                raise HTTPException(status_code=404, detail=f"备份 {name}[{index}] 资源不存在")

    for index, record in enumerate(payload.categories):
        kind = record.get("kind") or record.get("type") or "expense"
        if kind not in {"income", "expense"}:
            raise HTTPException(status_code=422, detail=f"备份 categories[{index}] 类型无效")
        if not str(record.get("name") or "").strip():
            raise HTTPException(status_code=422, detail=f"备份 categories[{index}] 名称不能为空")

    available_account_ids = {
        row.id for row in db.query(Account.id).filter(Account.user_id == user.id).all()
    }
    available_account_ids.update(item["id"] for item in payload.accounts)
    available_category_ids = {
        row.id for row in db.query(Category.id).filter(Category.user_id == user.id).all()
    }
    available_category_ids.update(item["id"] for item in payload.categories)
    for index, record in enumerate(payload.transactions):
        for field in ("account_id", "from_account_id", "to_account_id"):
            reference = record.get(field)
            if reference and reference not in available_account_ids:
                raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] 引用的账户不存在")
        reference = record.get("category_id")
        if reference and reference not in available_category_ids:
            raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] 引用的分类不存在")

    operation_ids: set[str] = set()
    for index, record in enumerate(payload.transactions):
        client_op_id = record.get("client_op_id")
        if payload.schema_version == 2 and (
            not isinstance(client_op_id, str) or not client_op_id or len(client_op_id) > 128
        ):
            raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] client_op_id 无效")
        if isinstance(client_op_id, str):
            if client_op_id in operation_ids:
                raise HTTPException(status_code=422, detail="备份 transactions 含重复 client_op_id")
            operation_ids.add(client_op_id)
            existing = (
                db.query(Transaction)
                .filter(
                    Transaction.user_id == user.id,
                    Transaction.client_op_id == client_op_id,
                )
                .first()
            )
            if existing and existing.id != record["id"]:
                raise HTTPException(status_code=409, detail="交易 client_op_id 已被其他交易使用")
        kind = record.get("kind") or record.get("type") or "expense"
        if kind not in {"income", "expense", "transfer"}:
            raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] 类型无效")
        currency = record.get("currency") or record.get("original_currency") or "CNY"
        if not isinstance(currency, str) or not 3 <= len(currency) <= 16:
            raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] 币种无效")
        _validate_date(
            record.get("occurred_on", record.get("date")),
            field="occurred_on",
            index=index,
            required=True,
        )
        _validate_date(record.get("exchange_rate_date"), field="exchange_rate_date", index=index)
        _validate_decimal(record.get("amount", record.get("original_amount")), field="amount", index=index, positive=True)
        if record.get("cny_amount") is not None:
            _validate_decimal(record["cny_amount"], field="cny_amount", index=index)
        if record.get("exchange_rate") is not None:
            _validate_decimal(record["exchange_rate"], field="exchange_rate", index=index, positive=True)
        if record.get("conversion_status") is not None and record["conversion_status"] not in {"ready", "pending"}:
            raise HTTPException(status_code=422, detail=f"备份 transactions[{index}] 换算状态无效")

    account_names: dict[str, str] = {}
    for index, record in enumerate(payload.accounts):
        name = str(record.get("name") or "").strip()
        if not name:
            raise HTTPException(status_code=422, detail=f"备份 accounts[{index}] 名称不能为空")
        kind = record.get("kind") or record.get("type") or "asset"
        if kind not in {"asset", "liability"}:
            raise HTTPException(status_code=422, detail=f"备份 accounts[{index}] 类型无效")
        account_kind = record.get("account_kind") or "other"
        if account_kind not in _ACCOUNT_KINDS:
            raise HTTPException(status_code=422, detail=f"备份 accounts[{index}] 用途无效")
        currency = record.get("currency") or "CNY"
        if not isinstance(currency, str) or not 3 <= len(currency) <= 16:
            raise HTTPException(status_code=422, detail=f"备份 accounts[{index}] 币种无效")
        _validate_date(record.get("opening_rate_date"), field="opening_rate_date", index=index)
        _validate_decimal(record.get("opening_balance", 0), field="opening_balance", index=index)
        for field in ("opening_cny_amount", "opening_exchange_rate"):
            _validate_decimal(record.get(field), field=field, index=index)
        active = record.get("deleted_at") is None
        folded = name.casefold()
        if active and folded in account_names and account_names[folded] != record["id"]:
            raise HTTPException(status_code=409, detail="备份 accounts 含重复名称")
        if active:
            account_names[folded] = record["id"]
            existing = (
                db.query(Account)
                .filter(Account.user_id == user.id, Account.deleted_at.is_(None))
                .all()
            )
            if any(
                row.id != record["id"] and row.name.strip().casefold() == folded
                for row in existing
            ):
                raise HTTPException(status_code=409, detail="账户名称不能重复")

    budget_keys: set[tuple[str, str]] = set()
    for index, record in enumerate(payload.budgets):
        month = record.get("month")
        category_id = record.get("category_id")
        if not isinstance(month, str) or not _MONTH_RE.fullmatch(month):
            raise HTTPException(status_code=422, detail=f"备份 budgets[{index}] 月份无效")
        if not isinstance(category_id, str) or not category_id or len(category_id) > 64:
            raise HTTPException(status_code=422, detail=f"备份 budgets[{index}] 分类无效")
        if category_id != "__total__" and category_id not in available_category_ids:
            raise HTTPException(status_code=422, detail=f"备份 budgets[{index}] 引用的分类不存在")
        _validate_decimal(record.get("limit"), field="limit", index=index, positive=True)
        key = (month, category_id)
        if key in budget_keys:
            raise HTTPException(status_code=409, detail="备份 budgets 含重复自然键")
        budget_keys.add(key)
        existing = budget_with_same_key(db, user, record)
        if existing and existing.id != record["id"]:
            raise HTTPException(status_code=409, detail="该月份和分类已有预算")


def _restore_deleted_timestamp(record: dict[str, Any], *, index: int) -> datetime | None:
    value = record.get("deleted_at")
    return None if value is None else _parse_timestamp(value, field="deleted_at", index=index)


def _apply_accounts(db: Session, user: User, records: list[dict[str, Any]]) -> int:
    count = 0
    for index, raw in enumerate(records):
        data = dict(raw)
        user.sync_version += 1
        db.flush()
        row = save_account(
            db,
            user,
            data,
            deleted=data.get("deleted_at") is not None,
            server_version=user.sync_version,
        )
        row.deleted_at = _restore_deleted_timestamp(data, index=index)
        db.flush()
        count += 1
    return count


def _apply_categories(db: Session, user: User, records: list[dict[str, Any]]) -> int:
    count = 0
    for raw in records:
        data = dict(raw)
        user.sync_version += 1
        db.flush()
        row = save_category(
            db,
            user,
            data,
            active=bool(data.get("active", True)),
            server_version=user.sync_version,
        )
        db.flush()
        count += 1
    return count


def _apply_budgets(db: Session, user: User, records: list[dict[str, Any]]) -> int:
    count = 0
    for index, raw in enumerate(records):
        data = dict(raw)
        user.sync_version += 1
        db.flush()
        row = save_budget(db, user, data, server_version=user.sync_version)
        row.active = bool(data.get("active", True))
        row.deleted_at = _restore_deleted_timestamp(data, index=index)
        db.flush()
        count += 1
    return count


def _apply_transactions(db: Session, user: User, records: list[dict[str, Any]]) -> int:
    count = 0
    for index, raw in enumerate(records):
        data = dict(raw)
        user.sync_version += 1
        db.flush()
        normalised = normalise_transaction_payload(
            attach_latest_rate(db, data),
            entity_id=data["id"],
        )
        # The regular entry path rounds CNY display values to cents. A backup
        # is a lossless storage boundary, so retain supplied Numeric values and
        # snapshots exactly when they are present in the file.
        raw_amount = data.get("amount", data.get("original_amount"))
        if raw_amount is not None:
            normalised["amount"] = Decimal(str(raw_amount))
        if data.get("cny_amount") is not None:
            normalised["cny_amount"] = Decimal(str(data["cny_amount"]))
        elif normalised["currency"] == "CNY":
            normalised["cny_amount"] = normalised["amount"]
        if data.get("exchange_rate") is not None:
            normalised["exchange_rate"] = Decimal(str(data["exchange_rate"]))
        if data.get("exchange_rate_date") is not None:
            normalised["exchange_rate_date"] = date_value(data["exchange_rate_date"])
        if "exchange_rate_source" in data:
            normalised["exchange_rate_source"] = data["exchange_rate_source"]
        if data.get("conversion_status") is not None:
            normalised["conversion_status"] = data["conversion_status"]
        row = save_transaction(
            db,
            user,
            normalised,
            deleted=data.get("deleted_at") is not None,
            server_version=user.sync_version,
        )
        row.deleted_at = _restore_deleted_timestamp(data, index=index)
        db.flush()
        count += 1
    return count


def _apply_profile(user: User, payload: RestoreIn) -> None:
    if payload.profile is None:
        return
    values = payload.profile.model_dump(exclude_unset=True)
    if "display_name" in values:
        if values["display_name"] is None or not str(values["display_name"]).strip():
            raise HTTPException(status_code=422, detail="profile.display_name 不能为空")
        user.display_name = str(values["display_name"]).strip()
    if "quick_memories" in values:
        user.quick_memories = values["quick_memories"]


def _invalidate_derived_data(db: Session, user_id: str) -> None:
    for model in (MonthlyReport, NetWorthSnapshot):
        db.query(model).filter(model.user_id == user_id).delete(synchronize_session=False)


def restore_backup(payload: RestoreIn, db: Session, user: User) -> dict[str, Any]:
    _validate_payload_limits(payload)
    if payload.owner_id is not None and payload.owner_id != user.id:
        raise HTTPException(status_code=422, detail="备份不属于当前用户")

    restore_id = payload.restore_id or str(uuid4())
    client_op_id = f"restore:{restore_id}"
    if len(client_op_id) > 128:
        raise HTTPException(status_code=422, detail="restore_id 过长")
    content_hash = _content_hash(payload)
    started_transaction = db.in_transaction()
    if not started_transaction:
        db.begin()
    try:
        locked_user = _lock_current_user(
            db,
            user.id,
            verified_auth_version=user.auth_version or 0,
        )
        previous = (
            db.query(SyncOperation)
            .filter(
                SyncOperation.user_id == locked_user.id,
                SyncOperation.client_op_id == client_op_id,
            )
            .first()
        )
        if previous is not None:
            if previous.entity_id != content_hash:
                raise HTTPException(status_code=409, detail="restore_id 已用于其他备份内容")
            return {
                "restored": True,
                "replayed": True,
                "restore_id": restore_id,
                "accounts": 0,
                "categories": 0,
                "transactions": 0,
                "budgets": 0,
                "server_version": previous.server_version,
            }

        # Perform database-dependent validation only after the user lock and
        # replay check. A reused restore_id therefore always gets the 409
        # contract before a changed payload can trigger another validation.
        _precheck_records(payload, db, locked_user)

        # Dependency order is deliberate: transactions can reference accounts
        # and categories restored in this same atomic transaction.
        accounts = _apply_accounts(db, locked_user, payload.accounts)
        categories = _apply_categories(db, locked_user, payload.categories)
        budgets = _apply_budgets(db, locked_user, payload.budgets)
        transactions = _apply_transactions(db, locked_user, payload.transactions)
        _apply_profile(locked_user, payload)
        applied_entities = accounts + categories + budgets + transactions
        if applied_entities:
            _invalidate_derived_data(db, locked_user.id)
        final_version = locked_user.sync_version
        db.add(
            SyncOperation(
                user_id=locked_user.id,
                client_op_id=client_op_id,
                entity="backup_restore",
                entity_id=content_hash,
                server_version=final_version,
            )
        )
        db.flush()
        db.commit()
        return {
            "restored": True,
            "replayed": False,
            "restore_id": restore_id,
            "accounts": accounts,
            "categories": categories,
            "transactions": transactions,
            "budgets": budgets,
            "server_version": final_version,
        }
    except BaseException:
        db.rollback()
        raise
