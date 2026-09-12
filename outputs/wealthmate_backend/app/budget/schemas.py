from decimal import Decimal

from pydantic import BaseModel, Field


class BudgetIn(BaseModel):
    id: str | None = None
    month: str = Field(pattern=r"^\d{4}-\d{2}$")
    category_id: str = Field(min_length=1, max_length=64)
    limit: Decimal = Field(gt=0)
    active: bool = True


class BudgetPatch(BaseModel):
    month: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}$")
    category_id: str | None = Field(default=None, min_length=1, max_length=64)
    limit: Decimal | None = Field(default=None, gt=0)
    active: bool | None = None
