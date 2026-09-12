from __future__ import annotations

from datetime import date

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from .db import SessionLocal
from .models import User
from .insights.service import scheduled_monthly_report
from .services.agent import configured_model


def previous_month(today: date | None = None) -> str:
    current = today or date.today()
    return f"{current.year - 1:04d}-12" if current.month == 1 else f"{current.year:04d}-{current.month - 1:02d}"


async def run_monthly_report_job() -> None:
    month = previous_month()
    db = SessionLocal()
    try:
        for user in db.query(User).all():
            await scheduled_monthly_report(
                db,
                user,
                month,
                model_factory=configured_model,
            )
        db.commit()
    finally:
        db.close()


def create_scheduler() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler()
    scheduler.add_job(run_monthly_report_job, "cron", day=1, hour=2, minute=0, id="monthly-report", replace_existing=True)
    return scheduler
