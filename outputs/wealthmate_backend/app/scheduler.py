from __future__ import annotations

from datetime import date

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from .api import _json_metrics, _records, _wealth
from .config import get_settings
from .db import SessionLocal
from .models import AgentLog, MonthlyReport, NetWorthSnapshot, User
from .domain import monthly_metrics
from .services.agent import configured_model, deterministic_report_text


def previous_month(today: date | None = None) -> str:
    current = today or date.today()
    return f"{current.year - 1:04d}-12" if current.month == 1 else f"{current.year:04d}-{current.month - 1:02d}"


async def run_monthly_report_job() -> None:
    month = previous_month()
    db = SessionLocal()
    try:
        for user in db.query(User).all():
            metrics = _json_metrics(monthly_metrics(_records(db, user), month))
            existing = db.query(MonthlyReport).filter(MonthlyReport.user_id == user.id, MonthlyReport.month == month).first()
            narrative = deterministic_report_text(metrics, None)
            ai_status = "unavailable"
            if get_settings().llm_provider.lower() not in ("", "none", "disabled"):
                try:
                    narrative, meta = await configured_model().complete("monthly_report", {"month": month, "metrics": metrics})
                    ai_status = "success"
                    db.add(AgentLog(user_id=user.id, task="monthly_report", model=meta.get("model"), status="success", input_tokens=meta.get("input_tokens"), output_tokens=meta.get("output_tokens"), result_summary="scheduled structured report"))
                except Exception as exc:
                    db.add(AgentLog(user_id=user.id, task="monthly_report", model=get_settings().llm_model or None, status="unavailable", result_summary=str(exc)))
            if existing:
                existing.metrics = metrics
                existing.narrative = narrative
                existing.ai_status = ai_status
            else:
                db.add(MonthlyReport(user_id=user.id, month=month, metrics=metrics, narrative=narrative, ai_status=ai_status))
            wealth = _wealth(db, user)
            snapshot = db.query(NetWorthSnapshot).filter(NetWorthSnapshot.user_id == user.id, NetWorthSnapshot.month == month).first()
            data = {"total_assets_cny": wealth["total_assets"], "total_liabilities_cny": wealth["total_liabilities"], "net_worth_cny": wealth["net_worth"], "pending_conversion_count": wealth["pending_conversion_count"]}
            if not snapshot:
                db.add(NetWorthSnapshot(user_id=user.id, month=month, **data))
        db.commit()
    finally:
        db.close()


def create_scheduler() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler()
    scheduler.add_job(run_monthly_report_job, "cron", day=1, hour=2, minute=0, id="monthly-report", replace_existing=True)
    return scheduler
