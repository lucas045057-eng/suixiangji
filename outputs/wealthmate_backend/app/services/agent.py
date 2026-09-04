from __future__ import annotations

import json
from typing import Any, Protocol

import httpx

from ..config import get_settings
from ..domain import classify_natural_language


class ModelAdapter(Protocol):
    async def complete(self, task: str, payload: dict[str, Any]) -> tuple[str, dict[str, Any]]: ...


class UnavailableModel:
    async def complete(self, task: str, payload: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        raise RuntimeError("LLM provider is not configured")


class OpenAICompatibleModel:
    async def complete(self, task: str, payload: dict[str, Any]) -> tuple[str, dict[str, Any]]:
        settings = get_settings()
        if not settings.llm_base_url or not settings.llm_model:
            raise RuntimeError("LLM provider is not configured")
        headers = {"content-type": "application/json"}
        if settings.llm_api_key:
            headers["authorization"] = f"Bearer {settings.llm_api_key}"
        system = "你是个人记账助手。只根据输入数据回答，不编造金额。记账只生成草稿，不能声称已经入账。"
        if task == "monthly_report":
            system = "你是个人财务分析助手。只解释给定结构化统计，不重新计算或添加不存在的金额；数据不足时明确说明。"
        async with httpx.AsyncClient(timeout=45) as client:
            response = await client.post(
                f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                headers=headers,
                json={"model": settings.llm_model, "temperature": 0.1, "messages": [{"role": "system", "content": system}, {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}]},
            )
            response.raise_for_status()
            data = response.json()
        content = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        return content, {"model": settings.llm_model, "input_tokens": usage.get("prompt_tokens"), "output_tokens": usage.get("completion_tokens")}


def configured_model() -> ModelAdapter:
    return OpenAICompatibleModel() if get_settings().llm_provider.lower() not in ("", "none", "disabled") else UnavailableModel()


async def make_draft(text: str, model: ModelAdapter | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
    from .agent_workflow import build_draft_graph

    state = await build_draft_graph(model or configured_model()).ainvoke({"text": text})
    return state["draft"], state.get("meta", {"status": "rules", "model": "rules"})


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
