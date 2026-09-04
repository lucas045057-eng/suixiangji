from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings


class Base(DeclarativeBase):
    pass


def _engine():
    url = get_settings().database_url
    kwargs = {"pool_pre_ping": True}
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
    """Apply additive V1.1 columns to databases created by the V1 release."""
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    additions = {
        "users": {
            "display_name": "VARCHAR(128) DEFAULT '财富用户'",
            "quick_memories": "JSON",
            "auth_version": "INTEGER DEFAULT 0",
        },
        "accounts": {
            "account_kind": "VARCHAR(32) DEFAULT 'other'",
            "is_liquid": "BOOLEAN DEFAULT FALSE",
            "is_default_payment": "BOOLEAN DEFAULT FALSE",
            "updated_at": "TIMESTAMP",
        },
        "transactions": {"occurred_at": "VARCHAR(64)"},
        "categories": {
            "active": "BOOLEAN DEFAULT TRUE",
            "server_version": "INTEGER DEFAULT 0",
            "updated_at": "TIMESTAMP",
        },
    }
    with engine.begin() as connection:
        for table, columns in additions.items():
            existing = {column["name"] for column in inspector.get_columns(table)}
            for column, declaration in columns.items():
                if column not in existing:
                    connection.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {declaration}"))
