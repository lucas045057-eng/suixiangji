from __future__ import annotations

from typing import Any, Literal, TypedDict


class StatsQuery(TypedDict, total=False):
    month: str
    period: Literal["day", "week", "month", "custom"]
    start: str
    end: str


class MonthlyReportResponse(TypedDict, total=False):
    id: str
    month: str
    metrics: dict[str, Any]
    summary: str
    ai_status: str
    generated_at: Any

