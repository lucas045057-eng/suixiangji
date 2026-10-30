import asyncio
from contextlib import suppress
import json

import httpx
import pytest
from sqlalchemy import event

from test_quick_entry_batch_api import api, batch_api
from batch_cases import TEXT, body, plan, simple_plan
from app.quick_entry import batch_llm, stream_llm, stream_router
from app.quick_entry.batch_schemas import DraftsIn
from app.quick_entry.stream_parser import PlanScanner, SSEDecoder, StreamFailure


def events(response):
    result = []
    for record in response.text.split("\n\n"):
        if not record or record.startswith(":"):
            continue
        lines = record.splitlines()
        value = json.loads(lines[2][6:])
        assert lines[0] == f'id: {value["request_id"]}:{value["seq"]}'
        assert lines[1] == f'event: {value["type"]}'
        assert value["seq"] == len(result) + 1
        assert value["stream_version"] == 1
        result.append(value)
    assert sum(e["type"] in ("completed", "error") for e in result) == 1
    return result


@pytest.fixture
def streaming(batch_api, monkeypatch):
    state = {"texts": [batch_api[3].content], "calls": 0, "closed": 0, "hook": None}

    async def fake(payload):
        state["calls"] += 1
        try:
            assert batch_api[1].kw["bind"].pool.checkedout() == 0
            yield "provider.connected", {}
            if state["hook"]:
                state["hook"]()
            text = state["texts"][min(state["calls"] - 1, len(state["texts"]) - 1)]
            if isinstance(text, Exception):
                raise text
            for char in text:
                yield "content", char
        finally:
            state["closed"] += 1

    monkeypatch.setattr(stream_llm, "stream_plan", fake)
    return *batch_api, state


def post(streaming, payload=None):
    client, _, auth, _, _ = streaming
    return client.post("/agent/drafts/stream", headers=auth, json=payload or body())


def test_final_result_identical_to_v1_and_stream_is_readonly(streaming, caplog):
    client, sessions, auth, stub, state = streaming
    writes = []

    def observe(conn, cursor, statement, params, context, many):
        if statement.lstrip().split()[0].upper() in ("INSERT", "UPDATE", "DELETE"):
            writes.append(statement)

    engine = sessions.kw["bind"]
    event.listen(engine, "before_cursor_execute", observe)
    try:
        response = post(streaming)
    finally:
        event.remove(engine, "before_cursor_execute", observe)
    assert writes == []
    assert response.headers["content-type"] == "text/event-stream; charset=utf-8"
    assert response.headers["cache-control"] == "no-cache, no-transform"
    assert response.headers["x-accel-buffering"] == "no"
    assert "content-length" not in response.headers and "content-encoding" not in response.headers
    stream = events(response)
    old = client.post("/agent/drafts", headers=auth, json=body())
    assert stream[-1]["data"]["result"] == old.json()
    p = next(e["data"] for e in stream if e["type"] == "item.preview")
    assert p["amount"] == "45.00" and p["is_approximate"]
    assert p["amount_range"]["upper"] == "50.00"
    assert p["preview_id"] == "a1-i0" and p["category_hint"] == "餐饮"
    ref = next(e["data"] for e in stream if e["type"] == "reference.preview")
    assert "amount" not in ref
    assert all(e["attempt"] == 1 for e in stream)
    assert state["closed"] == 1
    assert TEXT not in caplog.text and "吃饭吃了40多块" not in caplog.text


@pytest.mark.parametrize("corrupt", ["bad_quote", "bad_amount", "duplicate", "nan", "extra"])
def test_invalid_single_item_not_previewed_and_final_rejected(streaming, corrupt, caplog):
    semantic = plan()
    if corrupt == "bad_quote":
        semantic["items"][0]["quote"] = "private-provider-response"
    elif corrupt == "bad_amount":
        semantic["items"][0]["range"]["upper"] = "500"
    elif corrupt == "extra":
        semantic["items"][0]["private-provider-response"] = "secret"
    text = json.dumps(semantic, ensure_ascii=False)
    if corrupt == "duplicate":
        text = text.replace('"type": "expense"', '"type":"expense","type":"income"')
    if corrupt == "nan":
        text = text.replace('"amount_exact": null', '"amount_exact": NaN')
    streaming[4]["texts"] = [text]
    stream = events(post(streaming))
    assert not any(e["type"] == "item.preview" for e in stream)
    assert stream[-1]["data"]["code"] == "llm_bad_response"
    assert TEXT not in json.dumps(stream[-1]) and "private-provider-response" not in json.dumps(stream[-1])
    assert "private-provider-response" not in caplog.text
    assert streaming[4]["calls"] == (1 if corrupt in ("bad_quote", "bad_amount") else 2)


def test_retry_resets_attempt_but_not_sequence(streaming):
    good = streaming[4]["texts"][0]
    streaming[4]["texts"] = [good[:-1], good]
    stream = events(post(streaming))
    assert stream[-1]["type"] == "completed"
    restart = next(i for i, e in enumerate(stream) if e["type"] == "attempt.restarted")
    assert all(e["attempt"] == 1 for e in stream[:restart])
    assert all(e["attempt"] == 2 for e in stream[restart:])
    assert [e["data"]["preview_id"] for e in stream if e["type"] == "item.preview"] == ["a1-i0", "a2-i0"]
    assert streaming[4]["closed"] == 2


def test_missing_amount_and_transfer_and_preview_limit(streaming):
    text = "煎饼和豆浆"
    semantic = simple_plan(text, amount=None, amount_kind="missing")
    streaming[4]["texts"] = [json.dumps(semantic, ensure_ascii=False)]
    stream = events(post(streaming, body(text)))
    p = next(e["data"] for e in stream if e["type"] == "item.preview")
    assert p["amount"] is None
    assert stream[-1]["data"]["result"]["drafts"][0]["amount"] is None
    semantic["items"][0]["type"] = "transfer"
    streaming[4]["texts"] = [json.dumps(semantic, ensure_ascii=False)]
    assert not any(e["type"] == "item.preview" for e in events(post(streaming, body(text))))
    text = "咖啡各20元"
    semantic = simple_plan(text)
    semantic["items"] *= 9
    semantic["has_more_than_8_items"] = True
    streaming[4]["texts"] = [json.dumps(semantic, ensure_ascii=False)]
    stream = events(post(streaming, body(text)))
    assert len([e for e in stream if e["type"] == "item.preview"]) == 8
    assert stream[-1]["data"]["result"]["status"] == "needs_split"


def test_auth_rotation_during_generation(streaming):
    from app.models import User
    def rotate():
        with streaming[1].begin() as db:
            db.get(User, "batch-user").auth_version = 1
    streaming[4]["hook"] = rotate
    assert events(post(streaming))[-1]["data"]["code"] == "context_changed"


def test_before_first_frame_errors_and_shared_limit(streaming):
    client, _, auth, _, state = streaming
    for headers, payload, status in [({}, body(), 401), (auth, {**body(), "schema_version": 2}, 422),
                                     (auth, {**body(), "text": "x" * 1001}, 413)]:
        old = client.post("/agent/drafts", headers=headers, json=payload)
        new = client.post("/agent/drafts/stream", headers=headers, json=payload)
        assert new.status_code == old.status_code == status
        assert new.json() == old.json()
    bad = body()
    bad["ledger_context"]["fingerprint"] = " "
    assert post(streaming, bad).json()["code"] == "invalid_context"
    assert state["calls"] == 0
    from app.quick_entry.batch_router import drafts_limiter
    drafts_limiter.clear()
    for _ in range(19):
        assert client.post("/agent/drafts", headers=auth, json=body()).status_code == 200
    assert post(streaming).status_code == 200
    for path in ("/agent/drafts", "/agent/drafts/stream"):
        response = client.post(path, headers=auth, json=body())
        assert response.status_code == 429 and response.headers["retry-after"] == "60"


def test_scanner_only_emits_closed_top_level_objects():
    text = '😀午饭{\"items\":[]}20元'
    semantic = simple_plan(text, note='午饭{\"items\":[]}')
    semantic["reference"] = None
    # Reference preceding items and nested/unrelated keys must not confuse scanning.
    raw = json.dumps({"reference": None, **semantic}, ensure_ascii=False)
    scanner, found = PlanScanner(), []
    for char in raw:
        new = scanner.feed(char)
        if new:
            assert char == "}"
            found.extend(new)
    assert len(found) == 1
    assert json.loads(found[0][2]) == semantic["items"][0]
    assert scanner.content == raw


@pytest.mark.parametrize("size", [1, 2, 3, 7, 4096])
def test_sse_utf8_crlf_multiline_and_comments(size):
    raw = ': keep-alive\r\ndata: {"text":\r\ndata: "😀中文\\\"{}"}\r\n\r\ndata: [DONE]\n\n'.encode()
    decoder, records = SSEDecoder(), []
    for start in range(0, len(raw), size):
        records.extend(decoder.feed(raw[start:start + size]))
    records.extend(decoder.feed(b"", final=True))
    assert json.loads(records[0]) == {"text": '😀中文"{}'}
    assert records[1] == "[DONE]"


class BytesStream(httpx.AsyncByteStream):
    def __init__(self, data, size=1):
        self.data, self.size, self.closed = data, size, False
    async def __aiter__(self):
        for start in range(0, len(self.data), self.size):
            yield self.data[start:start + self.size]
    async def aclose(self):
        self.closed = True


def upstream_bytes(content, finish=True, done=True):
    frames = []
    for char in content:
        frames.append({"choices": [{"index": 0, "delta": {"content": char, "reasoning_content": "private-reasoning"}}]})
    if finish:
        frames.append({"choices": [{"delta": {}, "finish_reason": "stop"}]})
    frames.append({"choices": [], "usage": {"prompt_tokens": 1, "completion_tokens": 2}})
    raw = ": heartbeat\n\n" + "".join("data: " + json.dumps(f, ensure_ascii=False) + "\n\n" for f in frames)
    if done:
        raw += "data: [DONE]\n\ndata: invalid ignored after terminal\n\n"
    return raw.encode()


@pytest.mark.parametrize("mode,code", [("ok", None), ("eof", "stream_interrupted"),
    ("no_finish", "stream_interrupted"), ("bad", "stream_protocol_error"),
    ("utf8", "stream_protocol_error"), ("rate", "llm_rate_limited"),
    ("timeout", "llm_timeout"), ("connect", "llm_unavailable")])
def test_provider_framing_and_safe_errors(monkeypatch, mode, code, caplog):
    settings = batch_llm.get_settings()
    for key, value in {"llm_provider": "mock", "llm_model": "mock", "llm_base_url": "https://fake.test/v1"}.items():
        monkeypatch.setattr(settings, key, value)
    raw = upstream_bytes(json.dumps(plan(), ensure_ascii=False), finish=mode != "no_finish", done=mode != "eof")
    if mode == "bad": raw = b"data: private-provider-response\n\n"
    if mode == "utf8": raw = b"data: \xff\n\n"
    stream = BytesStream(raw)
    captured = []
    def transport(request):
        captured.append(json.loads(request.content))
        if mode == "timeout": raise httpx.ReadTimeout("private-provider-response")
        if mode == "connect": raise httpx.ConnectError("private-provider-response")
        return httpx.Response(429 if mode == "rate" else 200,
            headers={"content-type": "text/event-stream", "retry-after": "17"}, stream=stream)
    real = httpx.AsyncClient
    monkeypatch.setattr(batch_llm.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(transport), **kw))
    async def collect():
        return [e async for e in stream_llm.stream_plan({"text": TEXT})]
    if code:
        with pytest.raises(StreamFailure) as error:
            asyncio.run(collect())
        assert error.value.code == code
        if mode == "rate": assert error.value.retry_after_seconds == 17
    else:
        values = asyncio.run(collect())
        assert "".join(v for kind, v in values if kind == "content") == json.dumps(plan(), ensure_ascii=False)
    assert captured[0]["thinking"] == {"type": "disabled"}
    assert captured[0]["stream"] is True
    assert settings.llm_thinking_disabled is False
    assert "private-reasoning" not in caplog.text and TEXT not in caplog.text
    if mode not in ("timeout", "connect"): assert stream.closed


def test_heartbeat_deadline_cancel_and_terminal_cleanup(monkeypatch):
    monkeypatch.setattr(stream_router, "HEARTBEAT_SECONDS", 0.002)
    monkeypatch.setattr(stream_router, "TOTAL_SECONDS", 0.025)
    async def check():
        closed = []
        async def source():
            try:
                yield "session.started", {}, 1
                await asyncio.Event().wait()
            finally:
                closed.append(True)
        values = [v async for v in stream_router.event_stream(source(), "test-id-000")]
        assert ": keep-alive\n\n" in values
        assert '"code":"llm_timeout"' in values[-1]
        assert closed == [True]
        closed.clear()
        iterator = stream_router.event_stream(source(), "test-id-000")
        await anext(iterator)
        pending = asyncio.create_task(anext(iterator))
        await asyncio.sleep(0)
        pending.cancel()
        with suppress(asyncio.CancelledError): await pending
        await iterator.aclose()
        assert closed == [True]
        async def redundant():
            yield "completed", {"result": {}}, 1
            raise AssertionError("terminal must stop consumption")
        result = [v async for v in stream_router.event_stream(redundant(), "test-id-000")]
        assert len(result) == 1
    asyncio.run(check())


@pytest.mark.parametrize("mode", ["missing", "exact", "income", "range", "none", "overlap", "unresolved", "no_context"])
def test_final_parity_for_result_shapes(streaming, mode):
    payload, semantic = body(), plan()
    if mode in ("missing", "exact", "income"):
        text = "吃饭20元" if mode != "income" else "收到工资20元"
        payload = body(text)
        semantic = simple_plan(text)
        if mode == "missing":
            semantic["items"][0].update(amount_kind="missing", amount_exact=None)
        if mode == "income":
            semantic["items"][0].update(type="income", category_hint="工资")
    elif mode == "none":
        semantic.update(items=[], reference=None)
    elif mode == "unresolved":
        semantic.update(items=[], reference=None, unresolved=["transfer", "unsupported_reference"])
    elif mode == "overlap":
        semantic["items"] *= 2
    elif mode == "no_context":
        payload["ledger_context"] = None
    text = json.dumps(semantic, ensure_ascii=False)
    streaming[3].content = text
    streaming[4]["texts"] = [text]
    client, _, auth, _, _ = streaming
    old = client.post("/agent/drafts", headers=auth, json=payload)
    stream = events(post(streaming, payload))
    if old.status_code == 200:
        assert stream[-1]["data"]["result"] == old.json()
    else:
        assert stream[-1]["data"]["code"] == old.json()["code"]
        assert streaming[4]["calls"] == 1


@pytest.mark.parametrize("change", [
    {"quote": "fabricated"}, {"note": "invented"}, {"account_hint": "invented"},
    {"date_relation": "yesterday"}, {"date_relation": "explicit", "date": "2026-01-01"},
    {"currency": "USD"}, {"amount_kind": "missing", "amount_exact": "20"},
])
def test_single_preview_uses_existing_semantic_guards(change):
    """语义守卫保留（quote 不在正文即拒绝）；start/end 申报偏移由 reanchor 兜底（cc1709）。"""
    text = "吃饭20元"
    semantic = simple_plan(text)["items"][0]
    semantic.update(change)
    result = stream_router.preview("item", 0, json.dumps(semantic), DraftsIn.model_validate(body(text)), 1, [])
    assert result is None


def test_retry_switch_and_safe_endpoint_failure_codes(streaming, monkeypatch, caplog):
    monkeypatch.setattr(batch_llm.get_settings(), "llm_parse_retry", False)
    streaming[4]["texts"] = ["private-provider-response"]
    stream = events(post(streaming))
    assert stream[-1]["data"]["code"] == "llm_bad_response" and streaming[4]["calls"] == 1
    for code in stream_router.ERROR_MESSAGES:
        streaming[4]["texts"] = [StreamFailure(code, 7)]
        result = events(post(streaming))[-1]
        assert result["data"] == {"code": code, "message": stream_router.ERROR_MESSAGES[code], "retry_after_seconds": 7}
        assert TEXT not in json.dumps(result) and "private-provider-response" not in json.dumps(result)
    assert "private-provider-response" not in caplog.text


def test_bounded_parsers_reject_oversized_and_incomplete_utf8():
    with pytest.raises(StreamFailure, match="llm_bad_response"):
        PlanScanner().feed(" " * 65537)
    with pytest.raises(StreamFailure, match="stream_protocol_error"):
        SSEDecoder().feed(b"data: " + b"x" * 262145)
    decoder = SSEDecoder()
    decoder.feed(b"data: \xf0")
    with pytest.raises(StreamFailure, match="stream_protocol_error"):
        decoder.feed(b"", final=True)


@pytest.mark.parametrize("request_id", ["test\nnew-id", "test\rnew-id", "test\x00new-id"])
def test_unsafe_sse_id_is_rejected_before_first_frame(streaming, request_id):
    client, _, auth, _, state = streaming
    with client.stream("POST", "/agent/drafts/stream", headers=auth,
                       json={**body(), "request_id": request_id}) as response:
        assert response.status_code == 422
        assert response.headers["content-type"] == "application/json"
        content = b"".join(response.iter_bytes())
        assert json.loads(content) == {
            "detail": "请求格式不正确，请检查输入", "code": "validation_error",
        }
        assert b"data:" not in content
    assert response.is_closed and response.is_stream_consumed
    assert state["calls"] == state["closed"] == 0


@pytest.mark.parametrize("field,value,status,code", [
    ("text", "x" * 1001, 413, "text_too_large"),
    ("request_id", "x" * 64 + "\n", 422, "validation_error"),
])
def test_schema_length_checks_precede_sse_id_check(streaming, monkeypatch, field, value, status, code):
    def unexpected_route_validation(*args):
        pytest.fail("Schema-invalid requests must not reach the SSE id check")
    monkeypatch.setattr(stream_router, "BatchError", unexpected_route_validation)
    payload = {**body(), "request_id": "test\nnew-id", field: value}
    response = post(streaming, payload)
    assert response.status_code == status
    assert set(response.json()) == {"detail", "code"}
    assert response.json()["code"] == code
    assert response.is_closed and b"data:" not in response.content
    assert streaming[4]["calls"] == 0


def test_active_provider_is_closed_on_cancellation_without_writes(streaming, monkeypatch):
    sessions, closed, writes = streaming[1], [], []
    async def waiting(payload):
        try:
            yield "provider.connected", {}
            await asyncio.Event().wait()
        finally:
            closed.append(True)
    monkeypatch.setattr(stream_llm, "stream_plan", waiting)
    def observe(conn, cursor, statement, params, context, many):
        if statement.lstrip().split()[0].upper() in ("INSERT", "UPDATE", "DELETE"):
            writes.append(statement)
    engine = sessions.kw["bind"]
    event.listen(engine, "before_cursor_execute", observe)
    async def check():
        with sessions() as db:
            source = stream_router.generation(db, "batch-user", 0, DraftsIn.model_validate(body()), [])
            iterator = stream_router.event_stream(source, "test-id-000")
            await anext(iterator)
            await anext(iterator)
            assert not db.in_transaction()
            pending = asyncio.create_task(anext(iterator))
            await asyncio.sleep(0)
            pending.cancel()
            with suppress(asyncio.CancelledError): await pending
            await iterator.aclose()
    try:
        asyncio.run(check())
    finally:
        event.remove(engine, "before_cursor_execute", observe)
    assert closed == [True] and writes == []
