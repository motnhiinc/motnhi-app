"""authored stories: nullable owner on stories

Revision ID: c4b1f70a5d38
Revises: 0a3f7c1d9b22
Create Date: 2026-08-23 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c4b1f70a5d38'
down_revision: Union[str, Sequence[str], None] = '0a3f7c1d9b22'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('stories', sa.Column('owner_user_id', sa.String(), nullable=True))
    # Deliberately no ondelete: no content-table FK in this schema declares one,
    # so a DB-level user delete would cascade into stories and then fail against
    # story_pages. There is no user-delete endpoint today.
    op.create_foreign_key(
        'fk_stories_owner_user_id', 'stories', 'users', ['owner_user_id'], ['id']
    )
    op.create_index(
        op.f('ix_stories_owner_user_id'), 'stories', ['owner_user_id'], unique=False
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_stories_owner_user_id'), table_name='stories')
    op.drop_constraint('fk_stories_owner_user_id', 'stories', type_='foreignkey')
    op.drop_column('stories', 'owner_user_id')
