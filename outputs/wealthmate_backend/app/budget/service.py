from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from ..models import Budget, Category, User
from .domain import normalise_budget_values, TOTAL_BUDGET_CATEGORY
from .schemas import BudgetIn, BudgetPatch


def _json_metrics(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_metrics(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_metrics(item) for item in value]
    return value


def budget_json(row: Budget) -> dict:
    return _json_metrics({
        "id": row.id,
        "month": row.month,
        "category_id": row.category_id,
        "limit": row.limit,
        "active": row.active,
        "deleted_at": row.deleted_at,
        "server_version": row.server_version,
        "updated_at": row.updated_at,
    })


def save_budget(
    db: Session,
    user: User,
    values: dict,
    *,
    server_version: int | None = None,
) -> Budget:
    row = db.get(Budget, values["id"])
    if row and row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    existing = budget_with_same_key(db, user, values)
    if existing and existing.id != values['id']:
        raise HTTPException(status_code=409, detail='该月份和分类已有预算，请编辑已有预算')
    category_id = values.get("category_id")
    if category_id and category_id != TOTAL_BUDGET_CATEGORY:
        category = db.get(Category, category_id)
        if not category or category.user_id != user.id:
            raise HTTPException(status_code=422, detail=f"分类不存在: {category_id}")
        if category.kind != 'expense':
            raise HTTPException(status_code=422, detail='预算仅支持支出分类')
    data = normalise_budget_values({
        "month": values["month"],
        "category_id": values["category_id"],
        "limit": values["limit"],
        "active": bool(values.get("active", True)),
    })
    if not row:
        row = Budget(id=values["id"], user_id=user.id, **data)
        db.add(row)
    else:
        for key, value in data.items():
            setattr(row, key, value)
        row.deleted_at = None
    row.server_version = (
        server_version if server_version is not None else row.server_version
    )
    return row


def budget_with_same_key(db: Session, user: User, values: dict) -> Budget | None:
    # Tombstones also retain the database's natural key; reuse their identity.
    return db.query(Budget).filter(
        Budget.user_id == user.id,
        Budget.month == values.get('month'),
        Budget.category_id == values.get('category_id'),
    ).first()


def list_budgets(db: Session, user: User, month: str | None = None) -> dict:
    query = db.query(Budget).filter(
        Budget.user_id == user.id,
        Budget.deleted_at.is_(None),
        Budget.active.is_(True),
    )
    if month:
        query = query.filter(Budget.month == month)
    rows = query.order_by(Budget.month.desc(), Budget.updated_at.desc()).all()
    return {"items": [budget_json(row) for row in rows], "server_version": user.sync_version}


def create_budget(db: Session, user: User, payload: BudgetIn) -> dict:
    values = payload.model_dump()
    values["id"] = values.get("id") or str(uuid4())
    existing = budget_with_same_key(db, user, values)
    if existing and not payload.id:
        values["id"] = existing.id
    user.sync_version += 1
    row = save_budget(db, user, values, server_version=user.sync_version)
    db.commit()
    return budget_json(row)


def update_budget(
    db: Session,
    user: User,
    budget_id: str,
    payload: BudgetPatch,
) -> dict:
    row = db.get(Budget, budget_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    values = payload.model_dump(exclude_unset=True)
    values = {**budget_json(row), **values, "id": budget_id}
    user.sync_version += 1
    row = save_budget(db, user, values, server_version=user.sync_version)
    db.commit()
    return budget_json(row)


def delete_budget(db: Session, user: User, budget_id: str) -> dict:
    row = db.get(Budget, budget_id)
    if not row or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="预算不存在")
    user.sync_version += 1
    row.active = False
    row.deleted_at = datetime.now(timezone.utc)
    row.server_version = user.sync_version
    db.commit()
    return {"deleted": True, "id": budget_id, "server_version": user.sync_version}


# Compatibility names used by app.api's sync façade.
_budget_json = budget_json
_save_budget = save_budget
