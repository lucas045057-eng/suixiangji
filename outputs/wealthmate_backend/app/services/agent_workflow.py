from __future__ import annotations

from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from ..domain import classify_natural_language
from .agent import ModelAdapter


class DraftState(TypedDict, total=False):
    text: str
    draft: dict[str, Any]
    meta: dict[str, Any]
    model: ModelAdapter


def build_draft_graph(model: ModelAdapter):
    async def parse_rules(state: DraftState) -> DraftState:
        return {"draft": classify_natural_language(state["text"]), "model": model}

    def route(state: DraftState) -> str:
        draft = state["draft"]
        return "model" if draft.get("missing_fields") or draft.get("confidence", 0) < 0.85 else "finalize"

    async def model_review(state: DraftState) -> DraftState:
        draft = state["draft"]
        try:
            suggestion, meta = await state["model"].complete("draft", {"text": state["text"], "rules_draft": draft})
            return {"draft": {**draft, "ai_suggestion": suggestion, "requires_confirmation": True}, "meta": {"status": "success", **meta}}
        except Exception as exc:
            return {"draft": {**draft, "ai_unavailable": True, "ai_message": "AI 服务暂时不可用，请手动确认或补充信息"}, "meta": {"status": "unavailable", "result_summary": str(exc)}}

    def finalize(state: DraftState) -> DraftState:
        return {"meta": state.get("meta") or {"status": "rules", "model": "rules"}}

    graph = StateGraph(DraftState)
    graph.add_node("parse_rules", parse_rules)
    graph.add_node("model_review", model_review)
    graph.add_node("finalize", finalize)
    graph.add_edge(START, "parse_rules")
    graph.add_conditional_edges("parse_rules", route, {"model": "model_review", "finalize": "finalize"})
    graph.add_edge("model_review", "finalize")
    graph.add_edge("finalize", END)
    return graph.compile()
