import asyncio
import json

import httpx
import pytest

from app.config import Settings, get_settings
from app.quick_entry import batch_llm
from app.services.agent import OpenAICompatibleModel
from app.services import agent as agent_module
from app.services.llm_headers import INVALID_MESSAGE, extra_headers


def _configure(monkeypatch, **overrides):
    settings = get_settings()
    values = {
        "llm_provider": "mock",
        "llm_model": "test-model",
        "llm_base_url": "https://provider.test/v1",
        "llm_api_key": "test-only-key",
        "llm_extra_headers": "",
    }
    values.update(overrides)
    for name, value in values.items():
        monkeypatch.setattr(settings, name, value)
    return settings


def _patch_client(monkeypatch, captured, content="ok"):
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
    # batch_llm imports the same httpx module object.
    assert batch_llm.httpx is agent_module.httpx


def test_agent_adapter_sends_configured_extra_headers(monkeypatch):
    _configure(
        monkeypatch,
        llm_extra_headers=json.dumps({"x-opencode-session": "sess-123"}),
    )
    captured = []
    _patch_client(monkeypatch, captured)

    asyncio.run(OpenAICompatibleModel().complete("drafts", {"text": "hi"}))

    headers = captured[0].headers
    assert headers["x-opencode-session"] == "sess-123"
    assert headers["authorization"] == "Bearer test-only-key"
    assert headers["content-type"] == "application/json"


def test_empty_configuration_keeps_the_original_request_shape(monkeypatch):
    _configure(monkeypatch, llm_extra_headers="")
    captured = []
    _patch_client(monkeypatch, captured)

    asyncio.run(OpenAICompatibleModel().complete("drafts", {"text": "hi"}))

    headers = dict(captured[0].headers)
    assert headers["content-type"] == "application/json"
    assert headers["authorization"] == "Bearer test-only-key"
    # Only the adapter's own headers plus httpx's defaults; nothing extra.
    assert set(headers) <= {
        "content-type",
        "authorization",
        "host",
        "accept",
        "accept-encoding",
        "connection",
        "user-agent",
        "content-length",
    }


def test_blank_configuration_is_treated_as_absent(monkeypatch):
    assert extra_headers("") == {}
    assert extra_headers("   ") == {}
    assert extra_headers("{}") == {}

    _configure(monkeypatch, llm_extra_headers="  ")
    captured = []
    _patch_client(monkeypatch, captured)
    asyncio.run(OpenAICompatibleModel().complete("drafts", {"text": "hi"}))
    assert "x-opencode-session" not in captured[0].headers


@pytest.mark.parametrize(
    "raw",
    [
        "{",
        '"x"',
        '["x-opencode-session"]',
        '{"x-opencode-session": 1}',
        '{"x-opencode-session": null}',
        '{"": "value"}',
        '{"x-opencode-session": "a\\u0000b"}',
        '{"x-opencode-session": "a\\nb"}',
        '{"X-Opencode-Session": "a", "x-opencode-session": "b"}',
    ],
)
def test_invalid_configuration_fails_closed_without_any_request(monkeypatch, raw):
    _configure(monkeypatch, llm_extra_headers=raw)
    captured = []
    _patch_client(monkeypatch, captured)

    with pytest.raises(RuntimeError, match=INVALID_MESSAGE):
        asyncio.run(OpenAICompatibleModel().complete("drafts", {"text": "hi"}))
    assert captured == []


@pytest.mark.parametrize(
    "raw",
    [
        '{"authorization": "Bearer other"}',
        '{"Authorization": "Bearer other"}',
        '{"content-type": "text/plain"}',
        '{"Content-Type": "text/plain"}',
    ],
)
def test_reserved_headers_cannot_be_overridden(monkeypatch, raw):
    _configure(monkeypatch, llm_extra_headers=raw)
    captured = []
    _patch_client(monkeypatch, captured)

    with pytest.raises(RuntimeError, match=INVALID_MESSAGE):
        asyncio.run(OpenAICompatibleModel().complete("drafts", {"text": "hi"}))
    assert captured == []


def test_environment_value_is_read_by_settings(monkeypatch):
    monkeypatch.setenv(
        "WEALTHMATE_LLM_EXTRA_HEADERS", '{"x-opencode-session":"sess-env"}'
    )
    settings = Settings(_env_file=None)

    assert settings.llm_extra_headers == '{"x-opencode-session":"sess-env"}'
    assert extra_headers(settings.llm_extra_headers) == {
        "x-opencode-session": "sess-env"
    }


def test_cached_settings_pick_up_the_environment(monkeypatch):
    monkeypatch.setenv(
        "WEALTHMATE_LLM_EXTRA_HEADERS", '{"x-opencode-session":"sess-env"}'
    )
    get_settings.cache_clear()
    try:
        assert (
            get_settings().llm_extra_headers
            == '{"x-opencode-session":"sess-env"}'
        )
    finally:
        get_settings.cache_clear()


def test_batch_model_used_by_agent_drafts_sends_extra_headers(monkeypatch):
    _configure(
        monkeypatch,
        llm_extra_headers=json.dumps({"x-opencode-session": "sess-batch"}),
    )
    captured = []
    _patch_client(monkeypatch, captured, content="{}")

    content, _ = asyncio.run(
        batch_llm.BatchModel().complete("drafts", {"text": "午饭20元"})
    )

    assert content == "{}"
    headers = captured[0].headers
    assert headers["x-opencode-session"] == "sess-batch"
    assert headers["authorization"] == "Bearer test-only-key"


def test_batch_model_rejects_invalid_configuration(monkeypatch):
    _configure(monkeypatch, llm_extra_headers='{"authorization": "Bearer x"}')
    captured = []
    _patch_client(monkeypatch, captured, content="{}")

    with pytest.raises(RuntimeError, match=INVALID_MESSAGE):
        asyncio.run(batch_llm.BatchModel().complete("drafts", {"text": "x"}))
    assert captured == []
