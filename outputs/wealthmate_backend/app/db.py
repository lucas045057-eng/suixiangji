from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _engine():
    url = get_settings().database_url
    kwargs = {"pool_pre_ping": True, "hide_parameters": True}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
    return create_engine(url, **kwargs)


engine = _engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ensure_schema() -> None:
    """Check migration head; only explicit non-Beta test setup may create tables."""
    settings = get_settings()
    settings.validate_runtime()
    if settings.test_schema_init and settings.environment in ("development", "test"):
        Base.metadata.create_all(bind=engine)
        return
    with engine.connect() as connection:
        if "alembic_version" in inspect(connection).get_table_names():
            versions = connection.execute(text("SELECT version_num FROM alembic_version")).scalars().all()
            if versions == ["0002_beta_users"]:
                return
    raise RuntimeError("Database migration required: run alembic upgrade head before starting the API")
