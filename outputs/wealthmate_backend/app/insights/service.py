from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Callable, Literal, TYPE_CHECKING

from sqlalchemy.orm import Session

from ..config import get_settings
from ..domain import TransactionRecord, money
from ..services.agent import ModelAdapter, configured_model
from .domain import monthly_metrics, period_metrics

if TYPE_CHECKING:
    from ..models import User


def records(db: Session, user: User) -> list[TransactionRecord]:
    """Build a user-scoped read snapshot for all Insights calculations."""
    from ..models import Account, Transaction

    account_names = {
        row.id: row.name
        for row in db.query(Account).filter(Account.user_id == user.id).all()
    }
    return [
        TransactionRecord(
            row.id,
            row.kind,
            row.amount,
            row.currency,
            row.cny_amount,
            row.category_name,
            row.occurred_on,
            row.account_id,
            row.deleted_at is not None,
            row.occurred_at,
            account_names.get(row.account_id or ""),
        )
        for row in db.query(Transaction).filter(Transaction.user_id == user.id).all()
    ]


def json_metrics(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: json_metrics(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_metrics(item) for item in value]
    return value


def _date(value: str | date | None, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if value:
        return date.fromisoformat(value[:10])
    return fallback or date.today()


def _month_bounds(month: str) -> tuple[date, date]:
    year, month_number = map(int, month.split("-"))
    start = date(year, month_number, 1)
    end = date(year + (month_number == 12), 1 if month_number == 12 else month_number + 1, 1) - timedelta(days=1)
    return start, end


def stats(
    db: Session,
    user: User,
    *,
    month: str | None = None,
    period: Literal["day", "week", "month", "custom"] | None = None,
    start: str | None = None,
    end: str | None = None,
) -> dict[str, Any]:
    rows = records(db, user)
    if period is None:
        if month is None:
            raise ValueError("month 或 period 必须提供")
        range_start, range_end = _month_bounds(month)
        current = monthly_metrics(rows, month)
        aggregate = period_metrics(rows, "month", range_start, range_end)
        year, month_number = map(int, month.split("-"))
        previous = f"{year - 1:04d}-12" if month_number == 1 else f"{year:04d}-{month_number - 1:02d}"
        prior = monthly_metrics(rows, previous)
        current.update(aggregate)
        current["previous"] = prior
        current["expense_change"] = current["expense"] - prior["expense"]
        return json_metrics(current)

    if start is None:
        raise ValueError("period 统计必须提供 start")
    range_start = _date(start)
    if end is not None:
        range_end = _date(end)
    elif period == "day":
        range_end = range_start
    elif period == "week":
        range_end = range_start + timedelta(days=6)
    elif period == "month":
        range_end = date(range_start.year + (range_start.month == 12), 1 if range_start.month == 12 else range_start.month + 1, 1) - timedelta(days=1)
    else:
        range_end = range_start
    aggregate = period_metrics(rows, period, range_start, range_end)
    return json_metrics({
        "month": month or f"{range_start.year:04d}-{range_start.month:02d}",
        "income": aggregate["income_total"],
        "expense": aggregate["expense_total"],
        "balance": aggregate["net_worth_change"],
        "savings_rate": money(aggregate["net_worth_change"] / aggregate["income_total"] * 100) if aggregate["income_total"] else Decimal("0"),
        "category_totals": aggregate["expense_by_category"],
        "data_sufficient": bool(rows) and aggregate["pending_conversion_count"] == 0,
        **aggregate,
    })


def deterministic_report_text(metrics: dict[str, Any], previous: dict[str, Any] | None) -> str:
    if not metrics.get("data_sufficient"):
        return "当前数据不足，无法判断完整的月度财务情况。请补充账目或汇率后重新生成。"
    change = ""
    if previous:
        delta = metrics["expense"] - previous.get("expense", 0)
        change = f"与上月相比，本月支出变化为 {delta:.2f} 元。"
    advice = "建议继续保持当前记录习惯，并优先检查支出最高的分类。"
    if metrics["savings_rate"] < 20:
        advice = "本月储蓄率低于 20%，建议下月先为高频支出分类设置一个可执行上限。"
    return f"本月收入 {metrics['income']:.2f} 元，支出 {metrics['expense']:.2f} 元，结余 {metrics['balance']:.2f} 元，储蓄率 {metrics['savings_rate']:.2f}%。{change}{advice}"


deterministic_report = deterministic_report_text


def _compat_model_factory() -> Callable[[], ModelAdapter]:
    """Honor the old aggregate import while the route is being migrated."""
    try:
        from .. import api

        return api.configured_model
    except (AttributeError, ImportError):
        return configured_model


async def monthly_report(
    db: Session,
    user: User,
    month: str,
    *,
    force: bool = False,
    model_factory: Callable[[], ModelAdapter] | None = None,
) -> dict[str, Any]:
    from ..models import AgentLog, MonthlyReport

    existing = db.query(MonthlyReport).filter(
        MonthlyReport.user_id == user.id,
        MonthlyReport.month == month,
    ).first()
    if existing and not force:
        return {
            "id": existing.id,
            "month": existing.month,
            "metrics": existing.metrics,
            "summary": existing.narrative,
            "ai_status": existing.ai_status,
            "generated_at": existing.created_at,
        }
    metrics = stats(db, user, month=month)
    prior_report = db.query(MonthlyReport).filter(
        MonthlyReport.user_id == user.id,
        MonthlyReport.month != month,
    ).order_by(MonthlyReport.month.desc()).first()
    narrative = deterministic_report_text(metrics, prior_report.metrics if prior_report else None)
    ai_status = "unavailable"
    if get_settings().llm_provider.lower() not in ("", "none", "disabled"):
        try:
            model = (model_factory or _compat_model_factory())()
            narrative, meta = await model.complete("monthly_report", {"month": month, "metrics": metrics})
            ai_status = "success"
            db.add(AgentLog(
                user_id=user.id,
                task="monthly_report",
                model=meta.get("model"),
                status="success",
                input_tokens=meta.get("input_tokens"),
                output_tokens=meta.get("output_tokens"),
                result_summary="structured metrics only",
            ))
        except Exception:
            db.add(AgentLog(
                user_id=user.id,
                task="monthly_report",
                model=get_settings().llm_model or None,
                status="unavailable",
                result_summary="Provider unavailable; sensitive error details omitted",
            ))
    stored_metrics = json_metrics(metrics)
    if existing:
        existing.metrics = stored_metrics
        existing.narrative = narrative
        existing.ai_status = ai_status
        row = existing
    else:
        row = MonthlyReport(
            user_id=user.id,
            month=month,
            metrics=stored_metrics,
            narrative=narrative,
            ai_status=ai_status,
        )
        db.add(row)
    _save_net_worth_snapshot(db, user, month)
    db.commit()
    return {
        "id": row.id,
        "month": row.month,
        "metrics": metrics,
        "summary": narrative,
        "ai_status": ai_status,
        "generated_at": row.created_at,
    }


def _save_net_worth_snapshot(db: Session, user: User, month: str) -> None:
    from ..assets.service import wealth
    from ..models import NetWorthSnapshot

    wealth_data = wealth(db, user)
    snapshot = db.query(NetWorthSnapshot).filter(
        NetWorthSnapshot.user_id == user.id,
        NetWorthSnapshot.month == month,
    ).first()
    if snapshot:
        return
    db.add(NetWorthSnapshot(
        user_id=user.id,
        month=month,
        total_assets_cny=wealth_data["total_assets"],
        total_liabilities_cny=wealth_data["total_liabilities"],
        net_worth_cny=wealth_data["net_worth"],
        pending_conversion_count=wealth_data["pending_conversion_count"],
    ))


async def scheduled_monthly_report(
    db: Session,
    user: User,
    month: str,
    *,
    model_factory: Callable[[], ModelAdapter] | None = None,
) -> None:
    """Scheduler-facing operation; it preserves the existing outer transaction."""
    from ..models import AgentLog, MonthlyReport

    metrics = stats(db, user, month=month)
    existing = db.query(MonthlyReport).filter(
        MonthlyReport.user_id == user.id,
        MonthlyReport.month == month,
    ).first()
    narrative = deterministic_report_text(metrics, None)
    ai_status = "unavailable"
    if get_settings().llm_provider.lower() not in ("", "none", "disabled"):
        try:
            model = (model_factory or configured_model)()
            narrative, meta = await model.complete("monthly_report", {"month": month, "metrics": metrics})
            ai_status = "success"
            db.add(AgentLog(
                user_id=user.id,
                task="monthly_report",
                model=meta.get("model"),
                status="success",
                input_tokens=meta.get("input_tokens"),
                output_tokens=meta.get("output_tokens"),
                result_summary="scheduled structured report",
            ))
        except Exception:
            db.add(AgentLog(
                user_id=user.id,
                task="monthly_report",
                model=get_settings().llm_model or None,
                status="unavailable",
                result_summary="Provider unavailable; sensitive error details omitted",
            ))
    stored_metrics = json_metrics(metrics)
    if existing:
        existing.metrics = stored_metrics
        existing.narrative = narrative
        existing.ai_status = ai_status
    else:
        db.add(MonthlyReport(
            user_id=user.id,
            month=month,
            metrics=stored_metrics,
            narrative=narrative,
            ai_status=ai_status,
        ))
    _save_net_worth_snapshot(db, user, month)
