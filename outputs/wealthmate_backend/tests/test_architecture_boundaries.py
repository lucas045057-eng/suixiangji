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


def test_legacy_domain_module_is_only_compatibility_exports():
    source = (Path(__file__).parents[1] / "app" / "domain.py").read_text(
        encoding="utf-8"
    )
    for definition in (
        "def calculate_cny",
        "def classify_natural_language",
        "def push_idempotent",
        "def monthly_metrics",
        "def period_metrics",
    ):
        assert definition not in source


def test_legacy_schema_module_is_only_compatibility_exports():
    source = (Path(__file__).parents[1] / "app" / "schemas.py").read_text(
        encoding="utf-8"
    )
    assert "class " not in source
