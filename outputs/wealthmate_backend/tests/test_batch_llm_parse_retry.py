"""One silent retry when the provider returns an unparseable plan."""
import asyncio
import json

import httpx
import pytest

from app.config import get_settings
from app.quick_entry import batch_llm
from app.quick_entry.batch_schemas import BatchError

GOOD = '{"items":[],"reference":null,"has_more_than_8_items":false,"unresolved":[]}'
BAD = '{"items": [ this is not json'


def _configure(monkeypatch, **overrides):
    settings = get_settings()
    values = {
        "llm_provider": "mock",
        "llm_model": "test-model",
        "llm_base_url": "https://provider.test/v1",
        "llm_api_key": "test-only-key",
        "llm_extra_headers": "",
        "llm_parse_retry": True,
    }
    values.update(overrides)
    for name, value in values.items():
        monkeypatch.setattr(settings, name, value)


def _patch(monkeypatch, replies):
    """replies: list of content strings or httpx.Response statuses, consumed in order."""
    captured = []

    def transport(request):
        captured.append(request)
        reply = replies[min(len(captured) - 1, len(replies) - 1)]
        if isinstance(reply, int):
            return httpx.Response(reply, json={"detail": "upstream"})
        return httpx.Response(
            200,
            json={
                "choices": [{"message": {"content": reply}}],
                "usage": {"prompt_tokens": 5, "completion_tokens": 7},
            },
        )

    client_class = httpx.AsyncClient
    monkeypatch.setattr(
        batch_llm.httpx,
        "AsyncClient",
        lambda **kwargs: client_class(
            transport=httpx.MockTransport(transport), **kwargs
        ),
    )
    return captured


def _complete():
    return asyncio.run(batch_llm.BatchModel().complete("drafts", {"text": "午饭20元"}))


def test_malformed_then_valid_retries_exactly_once(monkeypatch):
    _configure(monkeypatch)
    captured = _patch(monkeypatch, [BAD, GOOD])

    content, meta = _complete()

    assert content == GOOD
    assert len(captured) == 2
    # Both attempts were billed, so their usage is summed.
    assert meta == {"input_tokens": 10, "output_tokens": 14}


def test_two_malformed_plans_raise_after_exactly_two_attempts(monkeypatch):
    _configure(monkeypatch)
    captured = _patch(monkeypatch, [BAD, BAD])

    with pytest.raises(BatchError) as caught:
        _complete()

    assert caught.value.code == "llm_bad_response"
    assert len(captured) == 2


def test_retry_can_be_disabled(monkeypatch):
    _configure(monkeypatch, llm_parse_retry=False)
    captured = _patch(monkeypatch, [BAD, GOOD])

    with pytest.raises(BatchError) as caught:
        _complete()

    assert caught.value.code == "llm_bad_response"
    assert len(captured) == 1


def test_transport_failures_are_not_retried(monkeypatch):
    _configure(monkeypatch)
    captured = _patch(monkeypatch, [503, GOOD])

    with pytest.raises(BatchError) as caught:
        _complete()

    assert caught.value.code == "llm_unavailable"
    assert len(captured) == 1


def test_retry_reuses_the_same_payload(monkeypatch):
    _configure(monkeypatch)
    captured = _patch(monkeypatch, [BAD, GOOD])

    _complete()

    bodies = [json.loads(request.content) for request in captured]
    assert bodies[0] == bodies[1]
    assert bodies[0]["temperature"] == 0
