"""`unresolved` tolerance: a provider may attach evidence to an entry.

The prompt asks for a list of enum strings; some plans instead carry
`{"kind": ..., "quote": ..., "start": ..., "end": ...}`. Only the white-listed
kind survives; every other shape still fails the plan as a whole.
"""
import json

import pytest

from app.quick_entry.batch_calculator import calculate_drafts
from app.quick_entry.batch_llm import parse_plan
from app.quick_entry.batch_schemas import BatchError, DraftsIn, SemanticPlan

from batch_cases import ACCOUNTS, CATEGORIES, body, item


def value(unresolved):
    plan = {
        "items": [item("今天喝咖啡花了9.9", "今天喝咖啡花了9.9", amount="9.9")],
        "reference": None,
        "has_more_than_8_items": False,
        "unresolved": unresolved,
    }
    return plan


def test_plain_enum_strings_still_validate():
    plan = parse_plan(json.dumps(value(["unsupported_reference", "transfer"])))
    assert plan.unresolved == ["unsupported_reference", "transfer"]


def test_object_entry_keeps_only_its_whitelisted_kind():
    raw = json.dumps(value([
        {"kind": "unsupported_reference", "quote": "两天前差不多", "start": 6, "end": 12},
    ]), ensure_ascii=False)
    plan = parse_plan(raw)
    assert plan.unresolved == ["unsupported_reference"]


def test_object_entry_with_unknown_kind_is_still_rejected():
    for junk in (
        [{"kind": "guess", "quote": "x", "start": 0, "end": 1}],
        [{"quote": "两天前差不多", "start": 6, "end": 12}],
        [{"kind": 3}],
    ):
        with pytest.raises(BatchError, match="llm_bad_response"):
            parse_plan(json.dumps(value(junk), ensure_ascii=False))


def test_mixed_array_accepts_codes_and_rejects_non_scalar_junk():
    plan = parse_plan(json.dumps(value([
        "transfer",
        {"kind": "ambiguous_total", "quote": "一共", "start": 0, "end": 2},
    ]), ensure_ascii=False))
    assert plan.unresolved == ["transfer", "ambiguous_total"]
    for junk in ([7], [["unsupported_reference"]], [None], [True]):
        with pytest.raises(BatchError, match="llm_bad_response"):
            parse_plan(json.dumps(value(junk)))


def test_tolerated_entry_reaches_the_calculator_as_a_notice():
    # The V1.0.8 report: "我今天消费和两天前差不多，只是多喝了杯咖啡花了9.9".
    text = "我今天消费和两天前差不多，只是多喝了杯咖啡花了9.9"
    payload = body(text)
    raw = json.dumps({
        "items": [item(text, "多喝了杯咖啡花了9.9", amount="9.9", note="咖啡")],
        "reference": None,
        "has_more_than_8_items": False,
        "unresolved": [{"kind": "unsupported_reference",
                        "quote": "两天前差不多", "start": 6, "end": 12}],
    }, ensure_ascii=False)
    plan = SemanticPlan.model_validate(json.loads(raw))
    result = calculate_drafts(DraftsIn.model_validate(payload), plan,
                              CATEGORIES, ACCOUNTS)
    assert result["status"] == "ok"
    assert [(draft["source"], draft["amount"], draft["date"])
            for draft in result["drafts"]] == [("explicit", "9.90", "2026-10-28")]
    assert [notice["code"] for notice in result["notices"]] == ["unsupported_reference"]
