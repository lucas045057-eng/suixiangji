from app.quick_entry.batch_calculator import (
    _CATEGORY_ALIASES, _category, calculate_drafts,
)
from app.quick_entry.batch_llm import SYSTEM_PROMPT
from app.quick_entry.batch_schemas import DraftsIn, SemanticPlan

from batch_cases import body, simple_plan


CATEGORIES = [
    {"id": "food", "name": "餐饮", "kind": "expense"},
    {"id": "transport", "name": "交通", "kind": "expense"},
    {"id": "salary", "name": "工资", "kind": "income"},
]


def resolve(hint, kind="expense", categories=CATEGORIES):
    return _category(hint, kind, categories)


def test_prompt_requires_copying_a_category_name_from_the_payload():
    prompt = SYSTEM_PROMPT
    assert "category_name" in prompt
    assert "逐字" in prompt
    assert "不得自造" in prompt
    assert "必须填null" in prompt
    # The existing safety rules must survive the wording change.
    assert "永远只是待确认草稿" in prompt
    assert "禁止输出最终卡、ID" in prompt


def test_exact_name_still_wins_before_any_alias():
    assert resolve("餐饮") == "food"
    assert resolve("交通") == "transport"


def test_normalised_names_match_width_case_and_spaces():
    assert resolve(" 餐饮 ") == "food"
    assert resolve("交　通") == "transport"
    assert resolve("Ｇｒｏｃｅｒｙ", categories=[
        {"id": "g", "name": "grocery", "kind": "expense"},
    ]) == "g"


def test_controlled_aliases_bridge_to_existing_names():
    assert resolve("打车") == "transport"
    assert resolve("网约车") == "transport"
    assert resolve("吃饭") == "food"
    assert resolve("外卖") == "food"
    assert resolve("咖啡") == "food"
    assert resolve("奖金", kind="income") == "salary"


def test_aliases_never_invent_a_missing_category():
    only_food = [{"id": "food", "name": "餐饮", "kind": "expense"}]
    assert resolve("打车", categories=only_food) is None
    assert resolve("电影", categories=only_food) is None
    assert resolve("理财", categories=only_food) is None


def test_aliases_respect_the_category_kind():
    # 工资 is an income category here, so an expense hint must not borrow it.
    assert resolve("奖金", kind="expense") is None
    assert resolve("奖金", kind="income") == "salary"


def test_ambiguous_duplicate_names_stay_unresolved():
    duplicated = [*CATEGORIES, {"id": "food-2", "name": "餐饮", "kind": "expense"}]
    assert resolve("餐饮", categories=duplicated) is None
    # The alias target must be unique as well.
    duplicated_transport = [
        *CATEGORIES, {"id": "transport-2", "name": "交通", "kind": "expense"},
    ]
    assert resolve("打车", categories=duplicated_transport) is None


def test_empty_hint_is_unresolved():
    assert resolve(None) is None
    assert resolve("") is None


def test_alias_table_stays_small_and_additive():
    # Default vocabulary v2 has 12 categories; ~4 aliases each is the ceiling.
    assert len(_CATEGORY_ALIASES) <= 60
    assert all(isinstance(key, str) and isinstance(value, str)
               for key, value in _CATEGORY_ALIASES.items())
    # An alias must never target another alias: the chain has exactly one hop.
    assert not set(_CATEGORY_ALIASES.values()) & set(_CATEGORY_ALIASES)


def test_default_vocabulary_v2_aliases_bridge_only_to_existing_names():
    v2 = [
        *CATEGORIES,
        {"id": "mobile", "name": "话费", "kind": "expense"},
        {"id": "utilities", "name": "水电", "kind": "expense"},
        {"id": "medical", "name": "药品", "kind": "expense"},
        {"id": "snacks", "name": "零食", "kind": "expense"},
        {"id": "social", "name": "人情往来", "kind": "expense"},
    ]
    assert resolve("话费", categories=v2) == "mobile"
    assert resolve("手机费", categories=v2) == "mobile"
    assert resolve("电费", categories=v2) == "utilities"
    assert resolve("买药", categories=v2) == "medical"
    assert resolve("小吃", categories=v2) == "snacks"
    assert resolve("红包", categories=v2) == "social"
    # Without the category the hint must stay unresolved instead of inventing one.
    assert resolve("手机费") is None
    assert resolve("电费") is None
    assert resolve("买药") is None
    # 转账 is not a category: the prompt routes it to unresolved/transfer.
    assert resolve("转账", categories=v2) is None


def test_every_alias_target_is_a_default_category_or_a_legacy_bridge():
    from app.auth.registration import DEFAULT_CATEGORIES

    defaults = {name for name, _ in DEFAULT_CATEGORIES}
    # Aliases may only point at a default name; legacy targets are gone.
    assert set(_CATEGORY_ALIASES.values()) <= defaults


def test_end_to_end_card_gets_the_bridged_category_id():
    text = "打车18元"
    semantic = simple_plan(text, "打车18元", amount="18", category_hint="打车")
    result = calculate_drafts(
        DraftsIn.model_validate(body(text)),
        SemanticPlan.model_validate(semantic),
        CATEGORIES, [],
    )
    assert result["drafts"][0]["category_id"] == "transport"


def test_end_to_end_unknown_hint_keeps_the_card_without_a_category():
    text = "理财18元"
    semantic = simple_plan(text, "理财18元", amount="18", category_hint="理财")
    result = calculate_drafts(
        DraftsIn.model_validate(body(text)),
        SemanticPlan.model_validate(semantic),
        CATEGORIES, [],
    )
    draft = result["drafts"][0]
    assert draft["category_id"] is None
    assert draft["amount"] == "18.00"
    assert "请选择分类" in draft["missing_facts"]
