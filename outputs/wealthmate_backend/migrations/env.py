from alembic import context
from sqlalchemy import create_engine, inspect, pool, text

from app.config import get_settings
from app.models import Base


def run_migrations():
    # Online only: legacy adoption requires inspecting existing schema/data.
    if context.is_offline_mode():
        raise RuntimeError("Legacy-safe migrations require an online database connection")
    engine = create_engine(get_settings().database_url, poolclass=pool.NullPool, hide_parameters=True)
    with engine.connect() as connection:
        if "users" in inspect(connection).get_table_names():
            collisions = connection.execute(text("SELECT count(*) FROM (SELECT lower(trim(username)) FROM users GROUP BY lower(trim(username)) HAVING count(*) > 1) AS collisions")).scalar()
            if collisions:
                raise RuntimeError("Username normalization collision: review existing accounts before migration; no records removed")
        connection.commit()
        context.configure(connection=connection, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


run_migrations()

