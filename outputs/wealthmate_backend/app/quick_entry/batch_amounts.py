"""Validate source evidence before trusting any semantic amount or date."""
from __future__ import annotations

import re
from datetime import timedelta
from decimal import Decimal

from ..assets.domain import money
from .batch_schemas import BatchError, DraftsIn, SemanticItem, SemanticPlan
from .domain import _amount_from_text, _parse_whole_yuan


_NUMBER = r"(?:[0-9]+(?:\.[0-9]{1,6})?|[零〇一二两三四五六七八九十百千万]+)"
_CURRENCY_WORDS = {
    "CNY": ("人民币", "元", "块", "¥", "￥"),
    "USD": ("美元", "美金", "刀", "$"),
    "EUR": ("欧元", "欧", "€"),
    "JPY": ("日元", "日币", "円"),
    "HKD": ("港元", "港币"),
    "GBP": ("英镑", "镑", "£"),
}


def currency_in_text(currency: str, text: str) -> bool:
    if re.search(r"(?<![A-Za-z])" + re.escape(currency) + r"(?![A-Za-z])", text, re.I):
        return True
    if currency == "CNY":
        foreign_removed = text
        for code, tokens in _CURRENCY_WORDS.items():
            if code != "CNY":
                for token in tokens:
                    foreign_removed = foreign_removed.replace(token, "")
        return any(token in foreign_removed for token in _CURRENCY_WORDS["CNY"])
    return any(
        token in text for token in _CURRENCY_WORDS.get(currency, ())
        if token not in ("刀", "欧")
    ) or (
        currency in ("USD", "EUR")
        and re.search(rf"{_NUMBER}{'刀' if currency == 'USD' else '欧'}", text) is not None
    )


def _normalized(text: str) -> str:
    return re.sub(r"\s+", "", text.translate(str.maketrans("０１２３４５６７８９．，", "0123456789.,"))).replace(",", "")


def _bounded_values(text: str):
    for match in re.finditer(rf"({_NUMBER})(?:多|来)(?:块钱|块|元|美元|欧元)?", text):
        if text[match.end():].startswith(("个", "次", "人", "件", "份")):
            continue
        lower = _parse_whole_yuan(match[1])
        if lower is None or lower <= 0 or lower != lower.to_integral_value():
            continue
        # 40多 -> [40,50), 100多 -> [100,200), 120多 -> [120,130).
        step = Decimal("1")
        while lower % (step * 10) == 0:
            step *= 10
        yield lower, lower + step, True, False
    for match in re.finditer(rf"({_NUMBER})(?:到|至|~|～|-)(?:({_NUMBER}))(?:块钱|块|元|美元|欧元)?", text):
        if text[match.end():].startswith(("个", "次", "人", "件", "份")):
            continue
        lower, upper = _parse_whole_yuan(match[1]), _parse_whole_yuan(match[2])
        if lower is not None and upper is not None and 0 <= lower < upper:
            yield lower, upper, True, True


def item_amount(item: SemanticItem) -> tuple[Decimal | None, dict | None, bool]:
    quote = _normalized(item.quote)
    if item.amount_kind == "missing":
        if item.amount_exact is not None or item.range is not None:
            raise BatchError("llm_bad_response")
        return None, None, False
    if item.amount_kind == "exact":
        if item.amount_exact is None or item.range is not None:
            raise BatchError("llm_bad_response")
        amount = Decimal(item.amount_exact)
        if amount <= 0 or list(_bounded_values(quote)) or re.search(
            r"几十|几百|几千|几万|一些|一点|很多钱|好多钱|(?:约|大概|大约)[0-9零〇一二两三四五六七八九十百千万]", quote
        ):
            raise BatchError("llm_bad_response")
        monetary_text = quote
        if item.currency:
            monetary_text = monetary_text.replace(item.currency, "元")
        for code in _CURRENCY_WORDS:
            if code in ("CNY", "USD"):
                continue
            monetary_text = monetary_text.replace(code, "元")
            for token in _CURRENCY_WORDS[code]:
                monetary_text = monetary_text.replace(token, "元")
        explicit = _amount_from_text(monetary_text)
        candidates = [explicit]
        if explicit is None:
            for match in re.finditer(
                rf"(?:花了?|付了?|消费|收入|支出|收到|到账|共|各)({_NUMBER})(?![0-9.])",
                quote,
            ):
                candidates.append(_parse_whole_yuan(match[1]))
            # Bare trailing amounts support “午饭20”, but never “20号/20个”.
            trailing = re.search(rf"({_NUMBER})$", quote)
            if trailing:
                candidates.append(_parse_whole_yuan(trailing[1]))
        if amount not in candidates or money(amount) <= 0:
            raise BatchError("llm_bad_response")
        return money(amount), None, False
    if item.range is None or item.amount_exact is not None:
        raise BatchError("llm_bad_response")
    bounds = item.range
    lower, upper = Decimal(bounds.lower), Decimal(bounds.upper)
    if not any(
        lower == lo and upper == hi and bounds.lower_inclusive == li
        and (bounds.upper_inclusive == ui or (ui and not bounds.upper_inclusive))
        for lo, hi, li, ui in _bounded_values(quote)
    ):
        raise BatchError("llm_bad_response")
    midpoint = money((lower + upper) / 2)
    if midpoint <= 0 or not money(lower) <= midpoint <= money(upper):
        raise BatchError("llm_bad_response")
    return midpoint, {
        "lower": format(money(lower), ".2f"),
        "upper": format(money(upper), ".2f"),
        "lower_inclusive": bounds.lower_inclusive,
        "upper_inclusive": bounds.upper_inclusive,
    }, True


def item_date(item: SemanticItem, payload: DraftsIn):
    if item.date_relation == "explicit":
        if item.date is None:
            raise BatchError("llm_bad_response")
        day = item.date
        chinese_day = f"{day.year}年{day.month}月{day.day}日"
        if day.isoformat() not in payload.text and chinese_day not in payload.text:
            raise BatchError("llm_bad_response")
        return day
    if item.date is not None:
        raise BatchError("llm_bad_response")
    if item.date_relation == "yesterday":
        if "昨天" not in payload.text or payload.local_today.toordinal() <= 1:
            raise BatchError("llm_bad_response")
        return payload.local_today - timedelta(days=1)
    return payload.local_today


def validate_plan(plan: SemanticPlan, payload: DraftsIn) -> None:
    sources = [*plan.items, *([plan.reference] if plan.reference else [])]
    for source in sources:
        if not 0 <= source.start < source.end <= len(payload.text) or payload.text[source.start:source.end] != source.quote:
            raise BatchError("llm_bad_response")
    if plan.reference:
        reference = plan.reference
        if not any(word in reference.quote for word in ("昨天", "昨日")) or not any(
            word in reference.quote for word in ("差不多", "一样", "相同", "照旧", "相近")
        ):
            raise BatchError("llm_bad_response")
        if reference.kind == "previous_day_total_expense" and reference.category_hint is not None:
            raise BatchError("llm_bad_response")
        if reference.kind == "previous_day_category_expense" and not reference.category_hint:
            raise BatchError("llm_bad_response")
    for index, item in enumerate(plan.items):
        if item.note and item.note not in item.quote:
            raise BatchError("llm_bad_response")
        if item.account_hint and item.account_hint not in payload.text:
            raise BatchError("llm_bad_response")
        currency = item.currency or payload.preferred_currency
        mentioned = {code for code in _CURRENCY_WORDS if currency_in_text(code, item.quote)}
        if mentioned and mentioned != {currency}:
            raise BatchError("llm_bad_response")
        if currency != payload.preferred_currency and not currency_in_text(currency, item.quote):
            raise BatchError("llm_bad_response")
        item_date(item, payload)
        item_amount(item)
        for previous in plan.items[:index]:
            if max(previous.start, item.start) < min(previous.end, item.end):
                if "各" not in payload.text[max(previous.start, item.start):min(previous.end, item.end)]:
                    raise BatchError("llm_bad_response")
                if previous == item:
                    raise BatchError("llm_bad_response")
