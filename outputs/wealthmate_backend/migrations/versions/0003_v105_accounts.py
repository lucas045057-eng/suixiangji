"""Account purpose and reversible archive; preserve all existing finance rows."""
from alembic import op
import sqlalchemy as sa

revision = '0003_v105_accounts'
down_revision = '0002_beta_users'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('accounts',sa.Column('note',sa.String(256),nullable=False,server_default=''))
    op.add_column('accounts',sa.Column('archived_at',sa.DateTime(timezone=True),nullable=True))


def downgrade():
    raise RuntimeError('Destructive downgrade disabled; retain archived accounts and purpose metadata')
