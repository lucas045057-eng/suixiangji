from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.orm import Session

from ..models import Account, AgentLog, Category, User
from ..services import agent
from .schemas import DraftIn


def _json_metrics(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_metrics(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_metrics(item) for item in value]
    return value


async def make_draft(db: Session, user: User, payload: DraftIn) -> dict:
    """Create a reviewable draft and record the agent invocation.

    This use case deliberately has no transaction persistence dependency. The
    confirmed posting decision belongs to the Ledger boundary.
    """
    draft, meta = await agent.make_draft(payload.text)
    if draft.get("account_hint"):
        account = (
            db.query(Account)
            .filter(
                Account.user_id == user.id,
                Account.name == draft["account_hint"],
                Account.deleted_at.is_(None),
            )
            .first()
        )
        if account:
            draft["account_id"] = account.id
    if draft.get("category_hint"):
        category = (
            db.query(Category)
            .filter(
                Category.user_id == user.id,
                Category.name == draft["category_hint"],
            )
            .first()
        )
        if category:
            draft["category_id"] = category.id
    db.add(
        AgentLog(
            user_id=user.id,
            task="draft",
            model=meta.get("model"),
            status=meta.get("status", "unknown"),
            input_tokens=meta.get("input_tokens"),
            output_tokens=meta.get("output_tokens"),
            result_summary=meta.get("result_summary") or "rules-first draft",
        )
    )
    db.commit()
    return _json_metrics(
        {
            **draft,
            "type": draft["kind"],
            "date": draft["occurred_on"],
            "account_name": draft.get("account_hint"),
            "category_name": draft.get("category_hint"),
            "currency": draft.get("currency", "CNY"),
        }
    )
