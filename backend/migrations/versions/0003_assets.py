"""assets table

Revision ID: 0a3f7c1d9b22
Revises: 7ecd8c44dd25
Create Date: 2026-06-26 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0a3f7c1d9b22'
down_revision: Union[str, Sequence[str], None] = '7ecd8c44dd25'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'assets',
        sa.Column('asset_id', sa.String(), nullable=False),
        sa.Column('kind', sa.Text(), nullable=False),
        sa.Column('storage_key', sa.Text(), nullable=False),
        sa.Column('content_type', sa.Text(), nullable=False),
        sa.Column('byte_size', sa.Integer(), nullable=True),
        sa.Column('duration_ms', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint('asset_id'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('assets')
