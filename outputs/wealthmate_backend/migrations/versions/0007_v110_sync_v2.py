"""V2 operation receipts, user protocol floor and singleton preferences."""
from alembic import op
import sqlalchemy as sa
revision = "0007_v110_sync_v2"
down_revision = "0006_v110_adjustments"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    if "min_client_protocol" not in {c["name"] for c in sa.inspect(bind).get_columns("users")}:
        op.add_column("users", sa.Column("min_client_protocol", sa.Integer, nullable=False, server_default="1"))
    existing = {c["name"] for c in sa.inspect(bind).get_columns("sync_operations")}
    for column in [sa.Column("protocol_version", sa.Integer, nullable=False, server_default="1"),
                   sa.Column("request_hash", sa.String(64), nullable=True),
                   sa.Column("result_json", sa.JSON(none_as_null=True), nullable=True)]:
        if column.name not in existing:
            op.add_column("sync_operations", column)
    if "user_preferences" not in sa.inspect(bind).get_table_names():
        op.create_table("user_preferences",
            sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), primary_key=True),
            sa.Column("default_account_id", sa.String(64), sa.ForeignKey("accounts.id"), nullable=True),
            sa.Column("server_version", sa.Integer, nullable=False),
            sa.Column("updated_at", sa.DateTime, nullable=False, server_default=sa.func.now()))


def downgrade():
    raise RuntimeError("Protocol floors and durable V2 receipts must be retained")
