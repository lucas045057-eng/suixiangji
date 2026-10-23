from __future__ import annotations

from typing import Any

from ..quick_entry.domain import classify_natural_language
from .agent import ModelAdapter


async def run_draft_workflow(
    text: str, model: ModelAdapter
) -> tuple[dict[str, Any], dict[str, Any]]:
    draft = classify_natural_language(text)
    if not draft.get("missing_fields") and draft.get("confidence", 0) >= 0.85:
        return draft, {"status": "rules", "model": "rules"}
    try:
        suggestion, meta = await model.complete(
            "draft", {"text": text, "rules_draft": draft}
        )
        return (
            {**draft, "ai_suggestion": suggestion, "requires_confirmation": True},
            {"status": "success", **meta},
        )
    except Exception as exc:
        return (
            {
                **draft,
                "ai_unavailable": True,
                "ai_message": "AI 服务暂时不可用，请手动确认或补充信息",
            },
            {"status": "unavailable", "result_summary": str(exc)},
        )
