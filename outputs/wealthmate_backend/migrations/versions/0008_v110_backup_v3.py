"""Tenant-owned FX history for lossless v3 backup restores."""
from alembic import op
import sqlalchemy as sa

revision = "0008_v110_backup_v3"
down_revision = "0007_v110_sync_v2"
branch_labels = None
depends_on = None


def upgrade():
    if "user_exchange_rates" not in sa.inspect(op.get_bind()).get_table_names():
        op.create_table("user_exchange_rates",
            sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("base_currency", sa.String(16), nullable=False),
            sa.Column("quote_currency", sa.String(16), nullable=False),
            sa.Column("rate", sa.Numeric(20, 10), nullable=False),
            sa.Column("rate_date", sa.Date, nullable=False),
            sa.Column("source", sa.String(256), nullable=False),
            sa.Column("fetched_at", sa.DateTime, server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("user_id", "base_currency", "quote_currency", "rate_date", "source",
                                name="uq_user_exchange_snapshot"))
        op.create_index("ix_user_exchange_rates_user_id", "user_exchange_rates", ["user_id"])


def downgrade():
    raise RuntimeError("Restored user FX history must be retained")
