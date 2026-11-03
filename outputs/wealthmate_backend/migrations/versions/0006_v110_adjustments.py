"""Add immutable adjustment storage without rewriting legacy financial rows."""
from alembic import op
import sqlalchemy as sa
revision = "0006_v110_adjustments"
down_revision = "0005_v110_account_safety"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    columns = {c["name"] for c in sa.inspect(bind).get_columns("transactions")}
    unique = {c["name"] for c in sa.inspect(bind).get_unique_constraints("transactions")}
    checks = {c["name"] for c in sa.inspect(bind).get_check_constraints("transactions")}
    fks = {c["name"] for c in sa.inspect(bind).get_foreign_keys("transactions")}
    with op.batch_alter_table("transactions") as batch:
        if "adjustment_meta" not in columns:
            batch.add_column(sa.Column("adjustment_meta", sa.JSON(none_as_null=True), nullable=True))
        if "reverses_transaction_id" not in columns:
            batch.add_column(sa.Column("reverses_transaction_id", sa.String(64), nullable=True))
        if "fk_transaction_reversal" not in fks:
            batch.create_foreign_key("fk_transaction_reversal", "transactions", ["reverses_transaction_id"], ["id"])
        if "uq_transaction_reversal" not in unique:
            batch.create_unique_constraint("uq_transaction_reversal", ["user_id", "reverses_transaction_id"])
        if "ck_transaction_adjustment" not in checks:
            batch.create_check_constraint("ck_transaction_adjustment", "kind != 'adjustment' OR (currency = 'CNY' AND amount != 0 AND cny_amount IS NOT NULL AND amount = cny_amount AND exchange_rate IS NOT NULL AND exchange_rate = 1 AND conversion_status = 'ready' AND account_id IS NOT NULL AND category_id IS NULL AND category_name IS NULL AND from_account_id IS NULL AND to_account_id IS NULL AND deleted_at IS NULL AND adjustment_meta IS NOT NULL)")
    if "ix_transaction_account_date" not in {i["name"] for i in sa.inspect(bind).get_indexes("transactions")}:
        op.create_index("ix_transaction_account_date", "transactions", ["user_id", "account_id", "occurred_on"])


def downgrade():
    raise RuntimeError("Adjustment history must be retained; use a compatible application version")
