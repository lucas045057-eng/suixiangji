"""Fixed inputs shared by batch unit and API tests; no provider is contacted."""
from copy import deepcopy
from datetime import date, timedelta


TEXT = "我今天消费跟昨天差不多，只有吃饭吃了40多块"
CATEGORIES = [
    {"id": "food", "name": "餐饮", "kind": "expense"},
    {"id": "transport", "name": "交通", "kind": "expense"},
    {"id": "salary", "name": "工资", "kind": "income"},
]
ACCOUNTS = [{"id": "wallet", "name": "微信", "currency": "CNY"}]


def body(text=TEXT, today="2026-10-28"):
    yesterday = date.fromisoformat(today) - timedelta(days=1)
    return {
        "schema_version": 1, "request_id": "test-batch-001", "text": text,
        "local_today": today, "utc_offset_minutes": 480, "preferred_currency": "CNY",
        "ledger_context": {
            "status": "ready", "target_date": today, "reference_date": yesterday.isoformat(),
            "fingerprint": "sha256:client-canonical-context-hash",
            "currencies": [{
                "currency": "CNY",
                "reference_day": {
                    "expense_total": "132.50", "expense_count": 3,
                    "category_totals": [
                        {"category_id": "food", "category_name": "餐饮", "expense_total": "45.00"},
                        {"category_id": "transport", "category_name": "交通", "expense_total": "18.00"},
                        {"category_id": "shopping", "category_name": "购物", "expense_total": "69.50"},
                    ],
                },
                "target_day": {"expense_total": "0.00", "expense_count": 0},
            }],
        },
    }


def item(text, quote, amount="20", **kwargs):
    start = text.index(quote)
    value = {
        "type": "expense", "quote": quote, "start": start, "end": start + len(quote),
        "amount_kind": "exact", "amount_exact": amount, "range": None,
        "currency": None, "date_relation": "today", "date": None,
        "category_hint": "餐饮", "account_hint": None, "note": "",
    }
    value.update(kwargs)
    return value


def reference(text=TEXT, quote="跟昨天差不多", **kwargs):
    start = text.index(quote)
    return {
        "kind": "previous_day_total_expense", "quote": quote,
        "start": start, "end": start + len(quote), **kwargs,
    }


def plan():
    return {
        "items": [item(
            TEXT, "吃饭吃了40多块", amount=None, amount_kind="bounded_range",
            range={"lower": "40", "upper": "50", "upper_inclusive": False},
            category_hint="餐饮", note="吃饭",
        )],
        "reference": reference(), "has_more_than_8_items": False, "unresolved": [],
    }


def simple_plan(text, quote=None, amount="20", **kwargs):
    return {
        "items": [item(text, quote or text, amount, **kwargs)],
        "reference": None, "has_more_than_8_items": False, "unresolved": [],
    }


def one_currency(payload, baseline, recorded="0", count=1):
    entry = payload["ledger_context"]["currencies"][0]
    entry["reference_day"].update(
        expense_total=baseline, expense_count=count, category_totals=[]
    )
    entry["target_day"].update(
        expense_total=recorded, expense_count=0 if recorded in ("0", "0.00") else 1
    )
    return entry


def with_currency(payload, code, baseline="100", recorded="0"):
    entry = deepcopy(payload["ledger_context"]["currencies"][0])
    entry["currency"] = code
    entry["reference_day"].update(
        expense_total=baseline, expense_count=1, category_totals=[]
    )
    entry["target_day"].update(
        expense_total=recorded, expense_count=0 if recorded == "0" else 1
    )
    payload["ledger_context"]["currencies"].append(entry)
    return entry
