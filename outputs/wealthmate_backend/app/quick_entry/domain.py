from __future__ import annotations

import re
from datetime import date
from decimal import Decimal
from typing import Any

from ..assets.domain import money


_CHINESE_DIGITS = {
    "零": 0,
    "〇": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
}
_CHINESE_SMALL_UNITS = {"十": 10, "百": 100, "千": 1000}
_FULLWIDTH_DIGITS = str.maketrans("０１２３４５６７８９．，", "0123456789.,")
_NUMBER_TOKEN = r"(?:\d+(?:\.\d{1,2})?|[零〇一二两三四五六七八九十百千万]+)"


def _parse_chinese_number(value: str) -> int | None:
    if not value:
        return None
    if value.isdigit():
        return int(value)
    if any(char not in _CHINESE_DIGITS and char not in _CHINESE_SMALL_UNITS and char != "万" for char in value):
        return None
    total = 0
    section = 0
    number = 0
    last_small_unit = None
    previous_digit = False
    previous_digit_value = None
    after_wan = False
    wan_tail_has_explicit_zero = False
    for char in value:
        if char in _CHINESE_DIGITS:
            digit = _CHINESE_DIGITS[char]
            if previous_digit and previous_digit_value != 0:
                return None
            number = digit
            if after_wan and digit == 0:
                wan_tail_has_explicit_zero = True
            previous_digit = True
            previous_digit_value = digit
        elif char in _CHINESE_SMALL_UNITS:
            unit = _CHINESE_SMALL_UNITS[char]
            if last_small_unit is not None and unit >= last_small_unit:
                return None
            section += (number or 1) * unit
            number = 0
            last_small_unit = unit
            previous_digit = False
            previous_digit_value = None
        elif char == "万":
            if total or section + number <= 0:
                return None
            total += (section + number) * 10000
            section = 0
            number = 0
            last_small_unit = None
            previous_digit = False
            previous_digit_value = None
            after_wan = True
            wan_tail_has_explicit_zero = False
    tail = section + number
    if after_wan and tail > 0 and section == 0 and last_small_unit is None and not wan_tail_has_explicit_zero:
        tail *= 1000
    return total + tail


def _parse_whole_yuan(value: str) -> Decimal | None:
    if re.fullmatch(r"\d+(?:\.\d{1,2})?", value):
        return Decimal(value)
    parsed = _parse_chinese_number(value)
    return Decimal(parsed) if parsed is not None else None


def _single_digit(value: str) -> int | None:
    if value.isdigit() and len(value) == 1:
        return int(value)
    if len(value) == 1 and value in _CHINESE_DIGITS:
        return _CHINESE_DIGITS[value]
    return None


def _fraction_from_suffix(suffix: str) -> Decimal | None:
    if not suffix:
        return Decimal("0")
    jiao_match = re.match(rf"(?P<jiao>{_NUMBER_TOKEN})(?:角|毛)(?P<rest>.*)", suffix)
    if jiao_match:
        jiao = _single_digit(jiao_match.group("jiao"))
        if jiao is None:
            return None
        rest = jiao_match.group("rest")
        if not rest:
            fen = 0
        else:
            fen_match = re.match(rf"(?P<fen>{_NUMBER_TOKEN})分?", rest)
            if not fen_match:
                return None
            fen = _single_digit(fen_match.group("fen"))
            if fen is None:
                return None
        return Decimal(jiao) / Decimal("10") + Decimal(fen) / Decimal("100")

    fen_match = re.match(rf"(?P<fen>{_NUMBER_TOKEN})分", suffix)
    if fen_match:
        fen = _single_digit(fen_match.group("fen"))
        return Decimal(fen) / Decimal("100") if fen is not None else None

    digit_tail = re.match(r"\d{1,2}", suffix)
    if digit_tail:
        raw = digit_tail.group(0)
        return Decimal(raw) / (Decimal("10") if len(raw) == 1 else Decimal("100"))

    chinese_tail = re.match(r"[零〇一二两三四五六七八九]{1,2}", suffix)
    if chinese_tail:
        cents = "".join(str(_CHINESE_DIGITS[char]) for char in chinese_tail.group(0))
        return Decimal(cents) / (Decimal("10") if len(cents) == 1 else Decimal("100"))

    return None


def _has_invalid_fraction_suffix(suffix: str) -> bool:
    if re.match(rf"^{_NUMBER_TOKEN}(?:厘|毫)", suffix):
        return True
    jiao_match = re.match(rf"^{_NUMBER_TOKEN}(?:角|毛)(?P<rest>.*)", suffix)
    if not jiao_match:
        return False
    rest = jiao_match.group("rest")
    second_unit = re.match(rf"^{_NUMBER_TOKEN}(?P<unit>分|厘|毫|角|毛)", rest)
    return second_unit is not None and second_unit.group("unit") != "分"


def _amount_from_text(text: str):
    normalized = re.sub(r"\s+", "", text.translate(_FULLWIDTH_DIGITS).replace(",", ""))
    match = re.search(
        rf"(?<![\d.])(?P<yuan>{_NUMBER_TOKEN})(?P<unit>块钱|元|块|人民币|CNY|USD|美元|刀)",
        normalized,
        re.I,
    )
    if not match:
        money_match = re.search(r"(?P<symbol>[¥￥])(?P<amount>\d+(?:\.\d{1,2})?)", normalized)
        if not money_match:
            return None
        amount = money(money_match.group("amount"))
        return amount if amount > 0 else None
    yuan = _parse_whole_yuan(match.group("yuan"))
    if yuan is None or yuan < 0:
        return None
    if "." in match.group("yuan"):
        amount = money(yuan)
        return amount if amount > 0 else None
    suffix = normalized[match.end() :]
    if _has_invalid_fraction_suffix(suffix):
        return None
    fraction = _fraction_from_suffix(suffix)
    amount = money(yuan + fraction) if fraction is not None else money(yuan)
    return amount if amount > 0 else None


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
    amount = _amount_from_text(text)
    missing_fields = []
    if amount is None or amount <= 0:
        missing_fields.append("amount")
    if account is None:
        missing_fields.append("account")
    missing_facts = [
        label
        for field, label in (("amount", "请输入金额"), ("account", "请选择支付账户"))
        if field in missing_fields
    ]
    return {
        "kind": kind,
        "amount": amount,
        "currency": currency,
        "category_hint": category,
        "account_hint": account,
        "occurred_on": occurred_on,
        "note": text.strip(),
        "confidence": 0.98 if category and account else 0.72,
        "requires_confirmation": True,
        "missing_fields": missing_fields,
        "missing_facts": missing_facts,
    }
