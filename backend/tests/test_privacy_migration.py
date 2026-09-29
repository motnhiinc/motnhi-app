from datetime import timedelta
from pathlib import Path
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
from sqlalchemy.engine import make_url
from sqlalchemy.schema import CreateSchema, DropSchema

from app.config import settings


@pytest.fixture
def migration_database(monkeypatch):
    engine = sa.create_engine(settings.test_database_url, future=True)
    schema = f"test_privacy_migration_{uuid4().hex}"

    with engine.begin() as connection:
        connection.execute(CreateSchema(schema))

    migration_url = make_url(settings.test_database_url).update_query_dict(
        {"options": f"-csearch_path={schema}"}
    )
    monkeypatch.setattr(
        settings,
        "database_url",
        migration_url.render_as_string(hide_password=False),
    )
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))

    try:
        command.upgrade(config, "c4b1f70a5d38")
        with engine.connect() as connection:
            connection.exec_driver_sql(f'SET search_path TO "{schema}"')
            yield connection, config
    finally:
        with engine.begin() as connection:
            connection.execute(DropSchema(schema, cascade=True))
        engine.dispose()


def test_privacy_migration_backfills_defaults(migration_database):
    connection, config = migration_database
    connection.execute(
        sa.text(
            """
            INSERT INTO users (id, auth_provider, created_at, updated_at)
            VALUES
                ('u1', 'device', now(), now()),
                ('u2', 'device', now(), now())
            """
        )
    )
    connection.commit()

    command.upgrade(config, "head")

    rows = connection.execute(
        sa.text("SELECT * FROM privacy_settings ORDER BY user_id")
    ).mappings().all()

    assert [row["user_id"] for row in rows] == ["u1", "u2"]
    for row in rows:
        assert row["accepted_policy_version"] is None
        assert row["core_storage_accepted_at"] is None
        assert row["progress_tracking_enabled"] is False
        assert row["cloud_tts_enabled"] is False
        assert row["page_image_validation_enabled"] is False
        assert row["last_active_at"] is not None
        assert row["last_active_at"].utcoffset() == timedelta(0)
        assert row["updated_at"] is not None
        assert row["updated_at"].utcoffset() == timedelta(0)

    connection.rollback()
    command.downgrade(config, "c4b1f70a5d38")

    inspector = sa.inspect(connection)
    assert not inspector.has_table("consent_events")
    assert not inspector.has_table("privacy_settings")
