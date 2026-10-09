"""Add pre-saved single-use recovery credential without changing user identity."""
from alembic import op
import sqlalchemy as sa
revision='0004_v105_recovery'
down_revision='0003_v105_accounts'
branch_labels=None
depends_on=None
def upgrade():
    op.add_column('users',sa.Column('recovery_code_hash',sa.String(256),nullable=True))
def downgrade():
    raise RuntimeError('Recovery credentials must not be dropped; restore a verified backup instead')
