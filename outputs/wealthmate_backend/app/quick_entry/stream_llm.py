"""OpenAI-compatible streaming adapter. Never logs upstream content."""
import json

import httpx

from ..services.llm_headers import extra_headers
from . import batch_llm
from .stream_parser import SSEDecoder, StreamFailure, strict_json


async def stream_plan(payload):
    settings = batch_llm.get_settings()
    if (settings.llm_provider.lower() in ("", "none", "disabled")
            or not settings.llm_base_url or not settings.llm_model):
        raise StreamFailure("llm_unavailable")
    # Streaming always disables thinking; the shared default leaves V1 intact.
    settings = settings.model_copy(update={"llm_thinking_disabled": True})
    headers = {"content-type": "application/json"}
    if settings.llm_api_key:
        headers["authorization"] = f"Bearer {settings.llm_api_key}"
    headers.update(extra_headers(settings.llm_extra_headers))
    body = {
        "model": settings.llm_model, "temperature": 0, "stream": True,
        "stream_options": {"include_usage": True},
        "messages": [
            {"role": "system", "content": batch_llm.SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ],
    }
    if settings.llm_thinking_disabled:
        body["thinking"] = {"type": "disabled"}
    try:
        async with httpx.AsyncClient(timeout=45) as client:
            async with client.stream(
                "POST", f"{settings.llm_base_url.rstrip('/')}/chat/completions",
                headers=headers, json=body,
            ) as response:
                if response.status_code == 429:
                    retry = response.headers.get("retry-after", "")
                    retry = int(retry) if retry.isascii() and retry.isdigit() and len(retry) <= 6 else None
                    raise StreamFailure("llm_rate_limited", retry)
                response.raise_for_status()
                if response.headers.get("content-type", "").split(";")[0].strip().lower() != "text/event-stream":
                    raise StreamFailure("stream_protocol_error")
                yield "provider.connected", {}
                decoder, finished = SSEDecoder(), False
                async for chunk in response.aiter_bytes():
                    for record in decoder.feed(chunk):
                        if record == "[DONE]":
                            if not finished:
                                raise StreamFailure("stream_interrupted")
                            return
                        try:
                            value = strict_json(record)
                            choices = value.get("choices", [])
                            if not isinstance(choices, list):
                                raise ValueError()
                            for choice in choices:
                                if choice.get("index", 0) != 0:
                                    continue
                                delta = choice.get("delta", {})
                                content = delta.get("content")
                                if content is not None and not isinstance(content, str):
                                    raise ValueError()
                                if finished and content:
                                    raise ValueError()
                                if content:
                                    yield "content", content
                                reason = choice.get("finish_reason")
                                if reason is not None:
                                    if reason != "stop" or finished:
                                        raise StreamFailure("stream_protocol_error")
                                    finished = True
                        except (ValueError, TypeError, AttributeError, RecursionError):
                            raise StreamFailure("stream_protocol_error") from None
                decoder.feed(b"", final=True)
                # A clean finish_reason is required *and* the provider's DONE.
                raise StreamFailure("stream_interrupted")
    except httpx.TimeoutException:
        raise StreamFailure("llm_timeout") from None
    except (httpx.RequestError, httpx.HTTPStatusError):
        raise StreamFailure("llm_unavailable") from None
