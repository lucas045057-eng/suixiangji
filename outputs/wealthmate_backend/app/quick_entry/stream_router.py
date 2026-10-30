"""Read-only generation stream; completed.result is the sole authoritative batch."""
import asyncio
from contextlib import aclosing, suppress
import json

import anyio
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import ValidationError
from sqlalchemy.orm import Session

from ..core.dependencies import get_current_user_readonly
from ..db import get_db
from ..models import Account, Category, User
from . import batch_llm, stream_llm
from .batch_amounts import item_amount, item_date, validate_plan
from .batch_calculator import calculate_drafts, validate_context
from .batch_router import DraftsRoute, drafts_limiter
from .batch_schemas import BatchError, DraftsIn, SemanticItem, SemanticPlan, SemanticReference
from .batch_service import _category_names
from .stream_parser import PlanScanner, StreamFailure, strict_json


router = APIRouter(route_class=DraftsRoute)
HEARTBEAT_SECONDS = 12
TOTAL_SECONDS = 60
ERROR_MESSAGES = {
    **{code: BatchError.MESSAGES[code][1] for code in (
        "llm_bad_response", "llm_timeout", "llm_unavailable")},
    "llm_rate_limited": "AI服务繁忙，请稍后再试",
    "context_changed": "登录或账本信息已变化，请重新整理",
    "stream_interrupted": "生成连接已中断，请重试或手动确认",
    "stream_protocol_error": "生成数据无效，请重试或手动确认",
}


def preview(tag, ordinal, raw, payload, attempt, category_names):
    try:
        value = strict_json(raw)
        if tag == "reference":
            source = SemanticReference.model_validate(value)
            plan = SemanticPlan(items=[], reference=source, has_more_than_8_items=False, unresolved=[])
            validate_plan(plan, payload)
            return "reference.preview", source.model_dump(mode="json")
        if ordinal >= 8:
            return None
        item = SemanticItem.model_validate(value)
        if item.type == "transfer":
            return None
        validate_plan(SemanticPlan(items=[item], has_more_than_8_items=False, unresolved=[]), payload)
        amount, bounds, approximate = item_amount(item)
        # A hint is display-only and may not introduce a provider's invented name.
        hint = item.category_hint
        if hint not in {row["name"] for row in category_names}:
            hint = None
        return "item.preview", {
            "preview_id": f"a{attempt}-i{ordinal}", "ordinal": ordinal,
            "type": item.type, "note": item.note,
            "source_quote": {"quote": item.quote, "start": item.start, "end": item.end},
            "amount_kind": item.amount_kind,
            "amount": format(amount, ".2f") if amount is not None else None,
            "amount_range": bounds, "is_approximate": approximate,
            "currency": item.currency or payload.preferred_currency,
            "date": item_date(item, payload).isoformat(),
            "category_hint": hint, "account_hint": item.account_hint,
        }
    except (BatchError, ValueError, TypeError, RecursionError, ValidationError):
        return None


def final_result(db, user_id, auth_version, payload, plan):
    with db.begin():
        current = db.get(User, user_id, populate_existing=True)
        if current is None or (current.auth_version or 0) != auth_version:
            raise StreamFailure("context_changed")
        categories = [
            {"id": row.id, "name": row.name, "kind": row.kind}
            for row in db.query(Category).filter(
                Category.user_id == user_id, Category.active.is_(True)).all()
        ]
        accounts = [
            {"id": row.id, "name": row.name, "currency": row.currency}
            for row in db.query(Account).filter(
                Account.user_id == user_id, Account.deleted_at.is_(None),
                Account.archived_at.is_(None)).all()
        ]
        return calculate_drafts(payload, plan, categories, accounts)


async def generation(db, user_id, auth_version, payload, category_names):
    yield "session.started", {}, 1
    upstream_payload = {
        "text": payload.text, "local_today": payload.local_today.isoformat(),
        "preferred_currency": payload.preferred_currency, "category_names": category_names,
        "ledger_context": payload.ledger_context.model_dump(mode="json") if payload.ledger_context else None,
    }
    attempts = 2 if batch_llm.get_settings().llm_parse_retry else 1
    for attempt in range(1, attempts + 1):
        if attempt > 1:
            yield "attempt.restarted", {}, attempt
        scanner, started = PlanScanner(), False
        try:
            async with aclosing(stream_llm.stream_plan(upstream_payload)) as upstream:
                async for kind, data in upstream:
                    if kind == "provider.connected":
                        yield kind, data, attempt
                    elif kind == "content":
                        if not started:
                            started = True
                            yield "generation.started", {}, attempt
                        for tag, ordinal, raw in scanner.feed(data):
                            result = preview(tag, ordinal, raw, payload, attempt, category_names)
                            if result:
                                yield *result, attempt
            yield "provider.completed", {}, attempt
            plan = batch_llm.parse_plan(scanner.content)
        except (BatchError, StreamFailure) as exc:
            if exc.code == "llm_bad_response" and attempt < attempts:
                continue
            raise
        # Semantic errors are deliberately outside the structural retry scope.
        validate_plan(plan, payload)
        yield "plan.validated", {}, attempt
        result = final_result(db, user_id, auth_version, payload, plan)
        yield "completed", {"result": result}, attempt
        return


async def event_stream(source, request_id):
    seq, attempt = 0, 1

    def frame(kind, data):
        nonlocal seq
        seq += 1
        envelope = {"stream_version": 1, "request_id": request_id, "seq": seq,
                    "attempt": attempt, "type": kind, "data": data}
        return (f"id: {request_id}:{seq}\nevent: {kind}\ndata: "
                + json.dumps(envelope, ensure_ascii=True, separators=(",", ":")) + "\n\n")

    task = None
    loop = asyncio.get_running_loop()
    deadline = loop.time() + TOTAL_SECONDS
    try:
        while True:
            if task is None:
                task = asyncio.create_task(anext(source))
            remaining = deadline - loop.time()
            if remaining <= 0:
                raise StreamFailure("llm_timeout")
            ready, _ = await asyncio.wait({task}, timeout=min(HEARTBEAT_SECONDS, remaining))
            if loop.time() >= deadline:
                raise StreamFailure("llm_timeout")
            if not ready:
                yield ": keep-alive\n\n"
                continue
            kind, data, attempt = task.result()
            task = None
            yield frame(kind, data)
            if kind in ("completed", "error"):
                return
    except asyncio.CancelledError:
        raise
    except Exception as exc:
        code = getattr(exc, "code", "stream_interrupted")
        if code not in ERROR_MESSAGES:
            code = "stream_interrupted"
        data = {"code": code, "message": ERROR_MESSAGES[code]}
        retry = getattr(exc, "retry_after_seconds", None)
        if type(retry) is int and retry >= 0:
            data["retry_after_seconds"] = retry
        yield frame("error", data)
    finally:
        # Starlette uses level cancellation on disconnect; shield resource close.
        with anyio.CancelScope(shield=True):
            if task is not None:
                task.cancel()
                with suppress(asyncio.CancelledError, Exception):
                    await task
            await source.aclose()


@router.post("/agent/drafts/stream")
async def agent_drafts_stream(
    payload: DraftsIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user_readonly),
):
    # SSE id cannot represent these values. Contract clarification pending;
    # reject before headers rather than enabling frame injection.
    if any(char in payload.request_id for char in ("\r", "\n", "\x00")):
        raise BatchError("validation_error")
    if not drafts_limiter.allow(user.id, 20):
        raise BatchError("rate_limited")
    validate_context(payload)
    user_id, auth_version = user.id, user.auth_version or 0
    with db.begin():
        category_names = _category_names(db, user_id)
    return StreamingResponse(
        event_stream(generation(db, user_id, auth_version, payload, category_names), payload.request_id),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache, no-transform", "X-Accel-Buffering": "no"},
    )
