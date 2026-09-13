from __future__ import annotations

import re
from datetime import date
from typing import Any

from ..assets.domain import money


def _amount_from_text(text: str):
    match = re.search(
        r"(?<!\d)(\d+(?:\.\d{1,2})?)(?:\s*)(?:元|块|人民币|CNY|USD|美元|刀)?",
        text,
        re.I,
    )
    return money(match.group(1)) if match else None


def classify_natural_language(text: str, *, today: date | None = None) -> dict[str, Any]:
    """Rules-first parser. Its output is always a draft and needs confirmation."""
    today = today or date.today()
    lowered = text.lower()
    kind = "income" if any(word in text for word in ("收入", "工资", "到账", "奖金", "收到")) else "expense"
    if any(word in text for word in ("转账", "转入", "转出")):
        kind = "transfer"
    currency = "USD" if any(word in lowered for word in ("usd", "美元")) else "CNY"
    category = None
    for keywords, label in (
        (("打车", "地铁", "公交", "交通"), "交通"),
        (("午饭", "晚饭", "早餐", "外卖", "餐饮", "吃饭"), "餐饮"),
        (("房租", "房贷"), "住房"),
        (("工资", "薪资"), "工资"),
        (("购物", "买了", "淘宝", "京东"), "购物"),
    ):
        if any(word in text for word in keywords):
            category = label
            break
    account = None
    for name in ("微信", "支付宝", "现金", "银行卡", "信用卡"):
        if name in text:
            account = name
            break
    occurred_on = today
    if "昨天" in text:
        occurred_on = today.fromordinal(today.toordinal() - 1)
    return {
        "kind": kind,
        "amount": _amount_from_text(text),
        "currency": currency,
        "category_hint": category,
        "account_hint": account,
        "occurred_on": occurred_on,
        "note": text.strip(),
        "confidence": 0.98 if category and account else 0.72,
        "requires_confirmation": True,
        "missing_fields": [
            field
            for field, value in (("amount", _amount_from_text(text)), ("account", account))
            if value is None
        ],
    }
