"""Deterministic Decimal calculation over validated semantics and local aggregates."""
from __future__ import annotations

import unicodedata
from datetime import timedelta
from decimal import Decimal

from ..assets.domain import money
from .batch_amounts import currency_in_text, item_amount, item_date, reanchor_plan, validate_plan
from .batch_schemas import BatchError, DraftsIn, ReadyContext, SemanticPlan


_MESSAGES = {
    "approximate_amount": "有界金额区间已按中值约记，可修改。",
    "reference_unavailable": "未找到可用的昨日已记支出参照，请手输今日总额。",
    "unsupported_reference": "暂只支持今天与昨天的支出参照，其余参照未折算。",
    "ambiguous_currency": "参照的币种口径不明确，未生成推算卡。",
    "ambiguous_total": "合计金额无法安全拆分，请手动确认。",
    "transfer_not_supported": "转账请使用现有手动转账入口。",
    "missing_amount": "明确事项存在未确定金额，请补全后重新解析参照。",
    "ambiguous_category": "分类口径不明确，参照未折算。",
    "non_positive_residual": "本次明确金额或今日已记金额已不低于昨日参照，请核对。",
    "residual_below_threshold": "其余差额较小，未生成推算卡。",
    "inferred_limit_reached": "已有8张明确卡，参照因上限未折算。",
    "needs_split": "内容超过8个独立事项，请分次说。",
    "no_actionable_items": "没有可安全生成的事项，请手动输入。",
}


def notice(code: str) -> dict:
    return {"code": code, "message": _MESSAGES[code]}


def validate_context(payload: DraftsIn) -> None:
    context = payload.ledger_context
    if not isinstance(context, ReadyContext):
        return
    if (
        payload.local_today.toordinal() <= 1
        or context.target_date != payload.local_today
        or context.reference_date != context.target_date - timedelta(days=1)
        or not context.fingerprint
        or context.fingerprint != context.fingerprint.strip()
        or any(ord(char) < 32 for char in context.fingerprint)
    ):
        raise BatchError("invalid_context")
    currencies = set()
    for entry in context.currencies:
        if entry.currency in currencies:
            raise BatchError("invalid_context")
        currencies.add(entry.currency)
        for day in (entry.reference_day, entry.target_day):
            if day.expense_count == 0 and Decimal(day.expense_total) != 0:
                raise BatchError("invalid_context")
        categories = entry.reference_day.category_totals
        ids = [row.category_id for row in categories]
        if (
            len(set(ids)) != len(ids)
            or sum((Decimal(row.expense_total) for row in categories), Decimal("0"))
            > Decimal(entry.reference_day.expense_total)
        ):
            raise BatchError("invalid_context")


# Controlled aliases: colloquial words a provider tends to emit → the exact
# category name a ledger may carry. An alias never creates a category: it only
# bridges to a name the user already has, otherwise the hint stays unresolved
# and the user picks manually. Keys are compared after normalisation
# (NFKC + casefold + whitespace removed), so no case/width variants are listed.
# Keep this table short and additive.
_CATEGORY_ALIASES = {
    # 餐饮
    "吃饭": "餐饮", "用餐": "餐饮", "外卖": "餐饮", "早餐": "餐饮",
    "午饭": "餐饮", "晚饭": "餐饮", "饮品": "餐饮", "咖啡": "餐饮",
    # 交通
    "打车": "交通", "出租车": "交通", "网约车": "交通", "地铁": "交通", "公交": "交通",
    # 购物
    "超市": "购物", "日用": "购物", "网购": "购物", "淘宝": "购物",
    # 娱乐
    "电影": "娱乐", "游戏": "娱乐", "唱歌": "娱乐", "聚会": "娱乐",
    # 住房
    "房租": "住房", "房贷": "住房", "物业": "住房",
    # 工资
    "薪水": "工资", "薪资": "工资", "奖金": "工资",
    # 稿费 (income): keep the colloquial 稿酬 bridged to the default name.
    "稿酬": "稿费", "稿费收入": "稿费",
    # 医疗/通讯 were never default names; their targets moved to the v2
    # defaults (药品/话费) so every alias stays a single hop to a real name.
    "看病": "药品", "挂号": "药品",
    # 话费 / 水电 / 药品 / 人情往来 (default vocabulary v2; 零食 was dropped
    # after round 3 — it pulled 水果/蛋糕 cards away from 餐饮)
    "手机费": "话费", "流量费": "话费", "宽带费": "话费",
    "电费": "水电", "水费": "水电", "燃气费": "水电", "水电煤": "水电",
    "买药": "药品", "药店": "药品", "医药": "药品", "药": "药品",
    "随礼": "人情往来", "份子钱": "人情往来", "红包": "人情往来",
}


def _normalize_name(value: str) -> str:
    """NFKC (full-width → half-width), trim, case-fold, drop inner spaces."""
    text = unicodedata.normalize("NFKC", value).strip().casefold()
    return text.replace(" ", "").replace("\t", "").replace("　", "")


def _category(hint, kind, categories):
    """Resolves a hint to an existing category of the same kind.

    Chain: exact name → normalised name → controlled alias. Every stage must
    match exactly one category of the right kind; duplicated names and aliases
    pointing at a name the user does not have resolve to None. This never
    invents a category: an unresolved hint still yields a card the user fills in.
    """
    if not hint:
        return None
    exact = [
        row for row in categories
        if row["kind"] == kind and row["name"] == hint
    ]
    if exact:
        return exact[0]["id"] if len(exact) == 1 else None
    normalized = _normalize_name(hint)
    loose = [
        row for row in categories
        if row["kind"] == kind and _normalize_name(row["name"]) == normalized
    ]
    if loose:
        return loose[0]["id"] if len(loose) == 1 else None
    canonical = _CATEGORY_ALIASES.get(normalized)
    if canonical is None:
        return None
    target = _normalize_name(canonical)
    matches = [
        row for row in categories
        if row["kind"] == kind and _normalize_name(row["name"]) == target
    ]
    return matches[0]["id"] if len(matches) == 1 else None


def _account(hint, currency, accounts):
    matches = [
        row for row in accounts if row["name"] == hint and row["currency"] == currency
    ]
    return matches[0]["id"] if len(matches) == 1 else None


def _source(source) -> dict:
    return {
        "kind": "source_text", "quote": source.quote,
        "start": source.start, "end": source.end,
    }


def _missing(amount, category_id, account_id):
    missing = []
    if amount is None:
        missing.append("请输入金额")
    if category_id is None:
        missing.append("请选择分类")
    if account_id is None:
        missing.append("请选择支付账户")
    return missing


def _response(payload, status, drafts, notices):
    return {
        "schema_version": 1, "request_id": payload.request_id,
        "status": status, "engine": "llm", "requires_confirmation": True,
        "drafts": drafts, "notices": notices,
    }


def _inferred(payload, reference, drafts, categories) -> tuple[dict | None, str | None]:
    context = payload.ledger_context
    if not isinstance(context, ReadyContext) or not context.currencies:
        return None, "reference_unavailable"
    currency = reference.currency
    if currency is None:
        if len(context.currencies) != 1:
            return None, "ambiguous_currency"
        currency = context.currencies[0].currency
        if currency != payload.preferred_currency:
            return None, "ambiguous_currency"
        if any(
            draft["currency"] != currency and draft["type"] == "expense"
            and draft["date"] == context.target_date.isoformat() for draft in drafts
        ):
            return None, "ambiguous_currency"
    elif len(context.currencies) > 1 and not currency_in_text(currency, reference.quote):
        return None, "ambiguous_currency"
    entry = next((row for row in context.currencies if row.currency == currency), None)
    if entry is None or entry.reference_day.expense_count == 0:
        return None, "reference_unavailable"
    category_id = category_hint = None
    category_scope = reference.kind == "previous_day_category_expense"
    if category_scope:
        category_hint = reference.category_hint
        category_id = _category(category_hint, "expense", categories)
        if category_id is None:
            return None, "reference_unavailable"
        category_total = next(
            (row for row in entry.reference_day.category_totals if row.category_id == category_id),
            None,
        )
        if category_total is None:
            return None, "reference_unavailable"
        baseline = money(Decimal(category_total.expense_total))
        # v1 has only today's total, so a nonzero category operand is unknowable.
        if Decimal(entry.target_day.expense_total) != 0:
            return None, "reference_unavailable"
        recorded = Decimal("0.00")
    else:
        baseline = money(Decimal(entry.reference_day.expense_total))
        recorded = money(Decimal(entry.target_day.expense_total))
    if baseline <= 0:
        return None, "reference_unavailable"
    eligible = [
        draft for draft in drafts if draft["type"] == "expense"
        and draft["currency"] == currency and draft["date"] == context.target_date.isoformat()
    ]
    if any(draft["amount"] is None for draft in eligible):
        return None, "missing_amount"
    if category_scope:
        if any(draft["category_id"] is None for draft in eligible):
            return None, "ambiguous_category"
        eligible = [draft for draft in eligible if draft["category_id"] == category_id]
    explicit = sum((Decimal(draft["amount"]) for draft in eligible), Decimal("0.00"))
    residual = baseline - recorded - explicit
    if residual <= 0:
        return None, "non_positive_residual"
    if residual < Decimal("10") or residual < baseline * Decimal("0.10"):
        return None, "residual_below_threshold"
    if len(drafts) == 8:
        return None, "inferred_limit_reached"
    result = format(money(residual), ".2f")
    context_evidence = {
        "kind": "ledger_context",
        "context_path": f"currencies.{currency}.reference_day",
        "reference_date": context.reference_date.isoformat(),
    }
    return {
        "client_draft_id": f"d{len(drafts) + 1}", "source": "inferred", "type": "expense",
        "amount": result, "amount_range": None, "is_approximate": True,
        "currency": currency, "category_hint": category_hint, "category_id": category_id,
        "account_hint": None, "account_id": None,
        "date": context.target_date.isoformat(), "note": "其他支出（按昨日推算）",
        "confidence": 0.60, "missing_facts": _missing(result, category_id, None),
        "selected_by_default": False, "evidence": [_source(reference), context_evidence],
        "derivation": {
            "kind": "previous_day_expense_residual",
            "reference_date": context.reference_date.isoformat(),
            "target_date": context.target_date.isoformat(),
            "operands": [
                {"key": "reference_expense", "label": "昨日已记消费",
                 "amount": format(baseline, ".2f"), "is_approximate": False},
                {"key": "target_recorded", "label": "今日已记消费",
                 "amount": format(recorded, ".2f"), "is_approximate": False},
                {"key": "explicit_candidates", "label": "本次明确卡合计",
                 "amount": format(explicit, ".2f"),
                 "is_approximate": any(draft["is_approximate"] for draft in eligible)},
            ],
            "formula": "reference_expense - target_recorded - explicit_candidates",
            "result": result, "context_fingerprint": context.fingerprint,
        },
    }, None


def calculate_drafts(payload: DraftsIn, plan: SemanticPlan, categories=(), accounts=()) -> dict:
    validate_context(payload)
    plan = reanchor_plan(payload, plan)
    validate_plan(plan, payload)
    if plan.has_more_than_8_items or len(plan.items) > 8:
        return _response(payload, "needs_split", [], [notice("needs_split")])
    drafts, notices = [], []
    for code in plan.unresolved:
        notices.append(notice("transfer_not_supported" if code == "transfer" else code))
    for item in plan.items:
        if item.type == "transfer":
            notices.append(notice("transfer_not_supported"))
            continue
        amount, amount_range, approximate = item_amount(item)
        currency = item.currency or payload.preferred_currency
        category_id = _category(item.category_hint, item.type, categories)
        account_id = _account(item.account_hint, currency, accounts)
        value = format(amount, ".2f") if amount is not None else None
        drafts.append({
            "client_draft_id": f"d{len(drafts) + 1}", "source": "explicit", "type": item.type,
            "amount": value, "amount_range": amount_range, "is_approximate": approximate,
            "currency": currency, "category_hint": item.category_hint, "category_id": category_id,
            "account_hint": item.account_hint, "account_id": account_id,
            "date": item_date(item, payload).isoformat(), "note": item.note or item.quote[:256],
            "confidence": 0.96 if amount is not None else 0.50,
            "missing_facts": _missing(value, category_id, account_id),
            "selected_by_default": True, "evidence": [_source(item)], "derivation": None,
        })
        if approximate:
            notices.append(notice("approximate_amount"))
    if plan.reference:
        inferred, code = _inferred(payload, plan.reference, drafts, categories)
        if inferred is not None:
            drafts.append(inferred)
        if code:
            notices.append(notice(code))
    if not drafts:
        notices.append(notice("no_actionable_items"))
    notices = list({row["code"]: row for row in notices}.values())
    return _response(payload, "ok" if drafts else "no_actionable_items", drafts, notices)
