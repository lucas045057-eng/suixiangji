"""Invite-only accounts and database-enforced case-insensitive username uniqueness."""
from alembic import op
import sqlalchemy as sa

revision = "0002_beta_users"
down_revision = "0001_legacy_baseline"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "invite_codes",
        sa.Column("code", sa.String(128), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("max_uses", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("used_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("max_uses > 0", name="ck_invite_max_uses"),
        sa.CheckConstraint("used_count >= 0 AND used_count <= max_uses", name="ck_invite_used_count"),
    )
    op.create_index("uq_users_username_normalized", "users", [sa.text("lower(trim(username))")], unique=True)


def downgrade():
    raise RuntimeError("Destructive downgrade disabled; no user or invitation records are removed")

