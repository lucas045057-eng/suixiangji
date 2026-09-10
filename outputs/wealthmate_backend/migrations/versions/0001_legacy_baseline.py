"""Adopt existing V1 tables or initialize a fresh database, add missing V1.1 columns.

No record, financial value, operation id or sync version is rewritten.
"""
from alembic import op
import sqlalchemy as sa

from migrations.legacy_schema import Base

revision = "0001_legacy_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    # Frozen schema, checkfirst: existing tables are left intact.
    Base.metadata.create_all(connection, checkfirst=True)
    additions = {
        "users": [
            sa.Column("display_name", sa.String(128), server_default="财富用户"),
            sa.Column("quick_memories", sa.JSON()),
            sa.Column("auth_version", sa.Integer(), server_default="0"),
        ],
        "accounts": [
            sa.Column("account_kind", sa.String(32), server_default="other"),
            sa.Column("is_liquid", sa.Boolean(), server_default=sa.false()),
            sa.Column("is_default_payment", sa.Boolean(), server_default=sa.false()),
            sa.Column("updated_at", sa.DateTime()),
        ],
        "transactions": [sa.Column("occurred_at", sa.String(64))],
        "categories": [
            sa.Column("active", sa.Boolean(), server_default=sa.true()),
            sa.Column("server_version", sa.Integer(), server_default="0"),
            sa.Column("updated_at", sa.DateTime()),
        ],
    }
    inspector = sa.inspect(connection)
    for table, columns in additions.items():
        existing = {column["name"] for column in inspector.get_columns(table)}
        for column in columns:
            if column.name not in existing:
                op.add_column(table, column)


def downgrade():
    raise RuntimeError("Destructive downgrade disabled; restore an operator-approved backup if required")

