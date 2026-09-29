"""add separately revocable page image validation consent"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0006_page_image_consent"
down_revision: Union[str, Sequence[str], None] = "9b6f5f37f8a1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "privacy_settings",
        sa.Column(
            "page_image_validation_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column("privacy_settings", "page_image_validation_enabled")
