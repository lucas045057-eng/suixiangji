"""V1 account safety: canonical names, deterministic repair and atomic audits."""
from datetime import datetime, timezone
from alembic import op
import sqlalchemy as sa
from app.assets.names import normalize_account_name, available_account_name

revision = "0005_v110_account_safety"
down_revision = "0004_v105_recovery"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    if "normalized_name" not in {c["name"] for c in sa.inspect(bind).get_columns("accounts")}:
        op.add_column("accounts", sa.Column("normalized_name", sa.String(512), nullable=True))
    if "account_mutation_audits" not in sa.inspect(bind).get_table_names():
        op.create_table("account_mutation_audits",
            sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
            sa.Column("user_id", sa.String(64), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("account_id", sa.String(64), nullable=False),
            sa.Column("client_op_id", sa.String(128), nullable=False),
            sa.Column("event_kind", sa.String(64), nullable=False),
            sa.Column("before_json", sa.JSON, nullable=False),
            sa.Column("after_json", sa.JSON, nullable=False),
            sa.Column("reason", sa.Text, nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.UniqueConstraint("user_id", "client_op_id", "event_kind", name="uq_account_audit_operation_event"))
        op.create_index("ix_account_mutation_audits_user_id", "account_mutation_audits", ["user_id"])
    meta = sa.MetaData()
    accounts = sa.Table("accounts", meta, autoload_with=bind)
    users = sa.Table("users", meta, autoload_with=bind)
    audits = sa.Table("account_mutation_audits", meta, autoload_with=bind)
    for user in bind.execute(sa.select(users.c.id, users.c.sync_version).order_by(users.c.id).with_for_update()).mappings().all():
        rows = bind.execute(sa.select(accounts).where(accounts.c.user_id == user["id"])
                            .order_by(accounts.c.server_version, accounts.c.id)).mappings().all()
        # Reserve all original names so a generated suffix cannot steal a later original.
        occupied = {normalize_account_name(row["name"]) for row in rows if row["deleted_at"] is None}
        seen = set()
        version = user["sync_version"]
        for row in rows:
            original = row["name"]
            normalized = normalize_account_name(original)
            name = original
            if row["deleted_at"] is None:
                if normalized in seen or not normalized or len(original) > 128:
                    name = available_account_name(original.strip(), row["id"], occupied)
                seen.add(normalized)
                occupied.add(normalize_account_name(name))
            data = {"normalized_name": normalize_account_name(name)}
            if name != original:
                version += 1
                data.update(name=name, server_version=version, updated_at=datetime.now(timezone.utc))
                operation_id = "migration:0005:" + row["id"]
                exists = bind.execute(sa.select(audits.c.id).where(audits.c.user_id == user["id"],
                    audits.c.client_op_id == operation_id, audits.c.event_kind == "migration_name_repaired")).first()
                if exists is None:
                    bind.execute(audits.insert().values(user_id=user["id"], account_id=row["id"],
                        client_op_id=operation_id, event_kind="migration_name_repaired",
                        before_json={"name": original}, after_json={"name": name},
                        reason="stable (server_version, id) duplicate-name migration"))
            bind.execute(accounts.update().where(accounts.c.id == row["id"]).values(**data))
        if version != user["sync_version"]:
            bind.execute(users.update().where(users.c.id == user["id"]).values(sync_version=version))
    if any(c["nullable"] for c in sa.inspect(bind).get_columns("accounts") if c["name"] == "normalized_name"):
        with op.batch_alter_table("accounts") as batch:
            batch.alter_column("normalized_name", existing_type=sa.String(512), nullable=False)
    if "uq_accounts_user_normalized_name" not in {i["name"] for i in sa.inspect(bind).get_indexes("accounts")}:
        op.create_index("uq_accounts_user_normalized_name", "accounts", ["user_id", "normalized_name"],
                        unique=True, sqlite_where=sa.text("deleted_at IS NULL"),
                        postgresql_where=sa.text("deleted_at IS NULL"))


def downgrade():
    raise RuntimeError("Account repairs and audits must be retained; restore a verified backup instead")
