from __future__ import annotations

import json
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Protocol

import httpx

from ..config import get_settings
from .llm_headers import extra_headers


def _json_safe(value: Any) -> Any:
    """Converts workflow leaf values so ``json.dumps`` cannot fail on them.

    Only the types this workflow produces are converted: ``Decimal`` becomes an
    exact decimal string (never a float, so 25.00 cannot drift) and dates use
    ISO 8601. A blanket ``default=str`` would stringify any unexpected object
    and hide the defect that produced it, which is exactly why the Decimal
    failure could go unnoticed; unknown types must still raise.
    """
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value


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
        headers.update(extra_headers(settings.llm_extra_headers))
        system = "你是个人记账助手。只根据输入数据回答，不编造金额。记账只生成草稿，不能声称已经入账。"
        if task == "monthly_report":
            system = "你是个人财务分析助手。只解释给定结构化统计，不重新计算或添加不存在的金额；数据不足时明确说明。"
        async with httpx.AsyncClient(timeout=45) as client:
            response = await client.post(
                f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                headers=headers,
                json={"model": settings.llm_model, "temperature": 0.1, "messages": [{"role": "system", "content": system}, {"role": "user", "content": json.dumps(_json_safe(payload), ensure_ascii=False)}]},
            )
            response.raise_for_status()
            data = response.json()
        content = data["choices"][0]["message"]["content"]
        usage = data.get("usage", {})
        return content, {"model": settings.llm_model, "input_tokens": usage.get("prompt_tokens"), "output_tokens": usage.get("completion_tokens")}


def configured_model() -> ModelAdapter:
    return OpenAICompatibleModel() if get_settings().llm_provider.lower() not in ("", "none", "disabled") else UnavailableModel()


async def make_draft(text: str, model: ModelAdapter | None = None) -> tuple[dict[str, Any], dict[str, Any]]:
    from .agent_workflow import run_draft_workflow

    return await run_draft_workflow(text, model or configured_model())
