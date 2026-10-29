"""Batch parsing coordinates short DB work around an entirely DB-free LLM wait."""
from __future__ import annotations

import re

import httpx
from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..config import get_settings
from ..models import Account, AgentLog, Category, User
from ..services.agent import ModelAdapter
from .batch_calculator import calculate_drafts, validate_context
from .batch_llm import BatchModel, parse_plan
from .batch_schemas import BatchError, DraftsIn


def _token_count(value):
    return value if type(value) is int and 0 <= value <= 2147483647 else None


def _record_log(db, user_id, status, meta, draft_count=0):
    allowed = {"ok", "needs_split", "no_actionable_items", *BatchError.MESSAGES}
    if status not in allowed:
        status = "internal_error"
    model = get_settings().llm_model
    model = model if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}", model) else None
    meta = meta if isinstance(meta, dict) else {}
    db.add(AgentLog(
        user_id=user_id, task="drafts", model=model, status=status,
        input_tokens=_token_count(meta.get("input_tokens")),
        output_tokens=_token_count(meta.get("output_tokens")),
        result_summary=f"schema_version=1;status={status};draft_count={draft_count}",
    ))


def _category_names(db: Session, user_id: str) -> list[dict]:
    """The provider's category vocabulary: names and kinds only.

    No ids, no totals, no ledger rows: the model may only copy a name, and the
    server resolves it against the database afterwards.
    """
    rows = db.query(Category.name, Category.kind).filter(
        Category.user_id == user_id, Category.active.is_(True)
    ).all()
    unique = {(row.name, row.kind) for row in rows}
    return [
        {"name": name, "kind": kind}
        for name, kind in sorted(unique, key=lambda pair: (pair[1], pair[0]))
    ]


def _failure_code(exc):
    if isinstance(exc, BatchError):
        return exc.code
    if isinstance(exc, (httpx.TimeoutException, TimeoutError)):
        return "llm_timeout"
    if isinstance(exc, (httpx.RequestError, httpx.HTTPStatusError)):
        return "llm_unavailable"
    return "internal_error"


async def make_drafts(
    db: Session, user: User, payload: DraftsIn, model: ModelAdapter | None = None
) -> dict:
    validate_context(payload)
    user_id, auth_version = user.id, user.auth_version or 0
    # Authentication has already detached the user and released its read transaction.
    meta = {}
    try:
        # A short read before the DB-free LLM wait: categories that have no
        # reference-day spend must still be visible to the model.
        with db.begin():
            category_names = _category_names(db, user_id)
        content, meta = await (model or BatchModel()).complete("drafts", {
            "text": payload.text,
            "local_today": payload.local_today.isoformat(),
            "preferred_currency": payload.preferred_currency,
            "category_names": category_names,
            "ledger_context": (
                payload.ledger_context.model_dump(mode="json")
                if payload.ledger_context is not None else None
            ),
        })
        plan = parse_plan(content)
        with db.begin():
            current = db.get(User, user_id, populate_existing=True)
            if current is None or (current.auth_version or 0) != auth_version:
                raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
            categories = [
                {"id": row.id, "name": row.name, "kind": row.kind}
                for row in db.query(Category).filter(
                    Category.user_id == user_id, Category.active.is_(True)
                ).all()
            ]
            accounts = [
                {"id": row.id, "name": row.name, "currency": row.currency}
                for row in db.query(Account).filter(
                    Account.user_id == user_id,
                    Account.deleted_at.is_(None), Account.archived_at.is_(None),
                ).all()
            ]
            result = calculate_drafts(payload, plan, categories, accounts)
            _record_log(db, user_id, result["status"], meta, len(result["drafts"]))
        return result
    except HTTPException:
        raise
    except Exception as exc:
        code = _failure_code(exc)
        db.rollback()
        try:
            with db.begin():
                if db.get(User, user_id) is not None:
                    _record_log(db, user_id, code, meta)
        except Exception:
            db.rollback()
        raise BatchError(code) from None
