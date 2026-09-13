"""Compatibility exports for the pre-modular backend schema imports."""

from .assets.schemas import AccountIn, RateIn
from .auth.schemas import DeleteUserIn, LoginIn, PasswordChange, ProfilePatch, RegisterIn
from .backup.schemas import RestoreIn
from .budget.schemas import BudgetIn, BudgetPatch
from .ledger.schemas import CategoryIn, CategoryPatch, TransactionIn
from .quick_entry.schemas import DraftIn
from .sync.schemas import SyncOperationIn, SyncPushIn


__all__ = [
    "AccountIn",
    "BudgetIn",
    "BudgetPatch",
    "CategoryIn",
    "CategoryPatch",
    "DeleteUserIn",
    "DraftIn",
    "LoginIn",
    "PasswordChange",
    "ProfilePatch",
    "RateIn",
    "RegisterIn",
    "RestoreIn",
    "SyncOperationIn",
    "SyncPushIn",
    "TransactionIn",
]
