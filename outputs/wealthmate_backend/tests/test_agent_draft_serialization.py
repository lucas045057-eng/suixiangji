import asyncio
import json
from datetime import date
from decimal import Decimal

import httpx
import pytest

from app.config import get_settings
from app.quick_entry.domain import classify_natural_language
from app.services import agent as agent_module
from app.services.agent import OpenAICompatibleModel, _json_safe
from app.services.agent_workflow import run_draft_workflow


def _configure(monkeypatch):
    settings = get_settings()
    for name, value in {
        "llm_provider": "mock",
        "llm_model": "test-model",
        "llm_base_url": "https://provider.test/v1",
        "llm_api_key": "test-only-key",
        "llm_extra_headers": "",
    }.items():
        monkeypatch.setattr(settings, name, value)


def _patch_client(monkeypatch, captured, content="用支付宝记"):
    def transport(request):
        captured.append(request)
        return httpx.Response(
            200,
            json={
                "choices": [{"message": {"content": content}}],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1},
            },
        )

    client_class = httpx.AsyncClient
    monkeypatch.setattr(
        agent_module.httpx,
        "AsyncClient",
        lambda **kwargs: client_class(
            transport=httpx.MockTransport(transport), **kwargs
        ),
    )


def test_legacy_draft_workflow_sends_a_json_payload_for_the_rules_draft(
    monkeypatch,
):
    # Pi D-2: the rules draft carries Decimal (amount) and date (occurred_on),
    # so json.dumps raised TypeError, run_draft_workflow swallowed it and the
    # provider was never contacted. The request must now actually go out.
    _configure(monkeypatch)
    captured = []
    _patch_client(monkeypatch, captured)

    rules = classify_natural_language("午饭25元")
    assert isinstance(rules["amount"], Decimal)
    assert isinstance(rules["occurred_on"], date)

    draft, meta = asyncio.run(
        run_draft_workflow("午饭25元", OpenAICompatibleModel())
    )

    assert len(captured) == 1
    request = json.loads(captured[0].content)
    payload = json.loads(request["messages"][1]["content"])
    assert payload["text"] == "午饭25元"
    assert payload["rules_draft"]["amount"] == "25.00"
    assert payload["rules_draft"]["occurred_on"] == date.today().isoformat()
    assert isinstance(payload["rules_draft"]["amount"], str)
    assert draft["ai_suggestion"] == "用支付宝记"
    assert "ai_unavailable" not in draft
    assert meta["status"] == "success"


def test_json_safe_converts_decimal_exactly_without_floats():
    value = _json_safe({"amount": Decimal("25.00"), "big": Decimal("1E+3")})
    assert value == {"amount": "25.00", "big": "1000"}


def test_json_safe_leaves_unknown_types_visible():
    # Deliberately not `default=str`: an unexpected object must still fail
    # loudly instead of being silently stringified.
    with pytest.raises(TypeError):
        json.dumps(_json_safe({"x": object()}))


def test_rules_first_answer_never_contacts_the_provider(monkeypatch):
    _configure(monkeypatch)
    captured = []
    _patch_client(monkeypatch, captured)

    draft, meta = asyncio.run(
        run_draft_workflow("午饭25元微信", OpenAICompatibleModel())
    )

    assert captured == []
    assert meta["status"] == "rules"
    assert "ai_unavailable" not in draft
