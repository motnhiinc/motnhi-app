"""privacy settings and consent events

Revision ID: 9b6f5f37f8a1
Revises: c4b1f70a5d38
Create Date: 2026-09-01 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "9b6f5f37f8a1"
down_revision: Union[str, Sequence[str], None] = "c4b1f70a5d38"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "privacy_settings",
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("accepted_policy_version", sa.Text(), nullable=True),
        sa.Column("core_storage_accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("progress_tracking_enabled", sa.Boolean(), nullable=False),
        sa.Column("cloud_tts_enabled", sa.Boolean(), nullable=False),
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("user_id"),
    )
    op.create_index(
        op.f("ix_privacy_settings_last_active_at"),
        "privacy_settings",
        ["last_active_at"],
        unique=False,
    )
    op.create_table(
        "consent_events",
        sa.Column("id", sa.String(), nullable=False),
        sa.Column("user_id", sa.String(), nullable=False),
        sa.Column("scope", sa.Text(), nullable=False),
        sa.Column("granted", sa.Boolean(), nullable=False),
        sa.Column("policy_version", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_consent_events_user_id"),
        "consent_events",
        ["user_id"],
        unique=False,
    )
    op.execute(
        """
        INSERT INTO privacy_settings (
            user_id, accepted_policy_version, core_storage_accepted_at,
            progress_tracking_enabled, cloud_tts_enabled, last_active_at, updated_at
        )
        SELECT id, NULL, NULL, FALSE, FALSE, now(), now()
        FROM users
        ON CONFLICT (user_id) DO NOTHING
        """
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f("ix_consent_events_user_id"), table_name="consent_events")
    op.drop_table("consent_events")
    op.drop_index(
        op.f("ix_privacy_settings_last_active_at"), table_name="privacy_settings"
    )
    op.drop_table("privacy_settings")
