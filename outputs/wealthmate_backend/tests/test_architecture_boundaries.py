from pathlib import Path


def test_models_py_is_the_only_sqlalchemy_model_module():
    backend = Path(__file__).parents[1] / "app"
    assert sorted(backend.rglob("models.py")) == [backend / "models.py"]
    for path in backend.rglob("*.py"):
        if path.name in {"models.py", "db.py"}:
            continue
        source = path.read_text(encoding="utf-8")
        assert "mapped_column(" not in source, path
        assert "Column(" not in source, path


def test_http_routers_do_not_commit_or_define_domain_calculations():
    backend = Path(__file__).parents[1] / "app"
    route_files = list(backend.rglob("router.py")) + [backend / "api.py"]
    for path in route_files:
        source = path.read_text(encoding="utf-8")
        assert "db.commit(" not in source, path
        assert "def monthly_metrics" not in source, path
        assert "def period_metrics" not in source, path


def test_legacy_compatibility_modules_are_removed():
    backend = Path(__file__).parents[1] / "app"
    for name in ("domain.py", "schemas.py", "security.py"):
        assert not (backend / name).exists(), name

    from app.assets.domain import calculate_cny, iso_date, money
    from app.assets.schemas import AccountIn, RateIn
    from app.auth.schemas import (
        DeleteUserIn,
        LoginIn,
        PasswordChange,
        ProfilePatch,
        RegisterIn,
    )
    from app.backup.schemas import RestoreIn
    from app.budget.schemas import BudgetIn, BudgetPatch
    from app.core.security import create_token, decode_token, hash_password, verify_password
    from app.insights.domain import (
        AccountRecord,
        TransactionRecord,
        monthly_metrics,
        period_metrics,
    )
    from app.ledger.schemas import CategoryIn, CategoryPatch, TransactionIn
    from app.quick_entry.domain import classify_natural_language
    from app.quick_entry.schemas import DraftIn
    from app.sync.schemas import SyncOperationIn, SyncPushIn

    assert all(
        value is not None
        for value in (
            AccountIn,
            AccountRecord,
            BudgetIn,
            BudgetPatch,
            CategoryIn,
            CategoryPatch,
            DeleteUserIn,
            DraftIn,
            LoginIn,
            PasswordChange,
            ProfilePatch,
            RateIn,
            RegisterIn,
            RestoreIn,
            SyncOperationIn,
            SyncPushIn,
            TransactionIn,
            TransactionRecord,
            calculate_cny,
            classify_natural_language,
            create_token,
            decode_token,
            hash_password,
            iso_date,
            money,
            monthly_metrics,
            period_metrics,
            verify_password,
        )
    )
