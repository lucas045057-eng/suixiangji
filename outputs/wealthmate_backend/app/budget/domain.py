from __future__ import annotations

from decimal import Decimal
from typing import Any, Mapping


def normalise_budget_values(values: Mapping[str, Any]) -> dict[str, Any]:
    """Normalise storage values without changing the public budget contract."""
    normalised = dict(values)
    normalised["limit"] = Decimal(str(normalised["limit"]))
    normalised["active"] = bool(normalised.get("active", True))
    return normalised
