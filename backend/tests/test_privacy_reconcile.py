from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select

import privacy_reconcile
from app.models import PrivacySettings, User
from tests.conftest import TestingSessionLocal

NOW = datetime(2026, 9, 3, 12, 0, 0, tzinfo=timezone.utc)


@pytest.fixture
def session_factory(db):
    def create():
        return TestingSessionLocal(bind=db.get_bind())

    return create


def _add_user(db, user_id):
    # No ORM relationship links users and privacy_settings, so the unit of
    # work will not order INSERTs across them: flush the user first.
    db.add(User(
        id=user_id,
        email=None,
        auth_provider="device",
        created_at=NOW,
        updated_at=NOW,
    ))
    db.flush()


def _add_consenting_user(db, user_id):
    _add_user(db, user_id)
    db.add(PrivacySettings(
        user_id=user_id,
        accepted_policy_version="2026-08-28",
        core_storage_accepted_at=NOW - timedelta(days=1),
        progress_tracking_enabled=True,
        cloud_tts_enabled=True,
        page_image_validation_enabled=False,
        last_active_at=NOW - timedelta(days=1),
        updated_at=NOW - timedelta(days=1),
    ))
    db.flush()


def _users_count(db):
    db.expire_all()
    return db.scalar(select(func.count()).select_from(User))


def _privacy_rows_count(db):
    db.expire_all()
    return db.scalar(select(func.count()).select_from(PrivacySettings))


def test_reconcile_inserts_default_rows_for_missing_users(db, session_factory, capsys):
    _add_user(db, "reconcile-missing-1")
    _add_user(db, "reconcile-missing-2")

    exit_code = privacy_reconcile.run_reconcile(
        session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    db.expire_all()
    for user_id in ("reconcile-missing-1", "reconcile-missing-2"):
        settings = db.get(PrivacySettings, user_id)
        assert settings is not None
        assert settings.accepted_policy_version is None
        assert settings.core_storage_accepted_at is None
        assert settings.progress_tracking_enabled is False
        assert settings.cloud_tts_enabled is False
        assert settings.last_active_at == NOW
        assert settings.updated_at == NOW
    assert capsys.readouterr().out.strip() == "created=2 users=2 privacy_rows=2"


def test_reconcile_preserves_existing_consent(db, session_factory):
    _add_consenting_user(db, "reconcile-existing")

    exit_code = privacy_reconcile.run_reconcile(
        session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    db.expire_all()
    settings = db.get(PrivacySettings, "reconcile-existing")
    assert settings.accepted_policy_version == "2026-08-28"
    assert settings.core_storage_accepted_at == NOW - timedelta(days=1)
    assert settings.progress_tracking_enabled is True
    assert settings.cloud_tts_enabled is True
    assert settings.last_active_at == NOW - timedelta(days=1)
    assert settings.updated_at == NOW - timedelta(days=1)


def test_reconcile_is_idempotent(db, session_factory, capsys):
    _add_consenting_user(db, "reconcile-idempotent-consent")
    _add_user(db, "reconcile-idempotent-missing")

    first = privacy_reconcile.run_reconcile(
        session_factory=session_factory, now=NOW
    )
    second = privacy_reconcile.run_reconcile(
        session_factory=session_factory, now=NOW
    )

    assert first == 0
    assert second == 0
    assert capsys.readouterr().out.splitlines() == [
        "created=1 users=2 privacy_rows=2",
        "created=0 users=2 privacy_rows=2",
    ]
    assert _privacy_rows_count(db) == 2


def test_reconcile_achieves_one_row_per_user(db, session_factory):
    _add_consenting_user(db, "reconcile-count-consent")
    _add_user(db, "reconcile-count-missing-a")
    _add_user(db, "reconcile-count-missing-b")

    exit_code = privacy_reconcile.run_reconcile(
        session_factory=session_factory, now=NOW
    )

    assert exit_code == 0
    assert _users_count(db) == _privacy_rows_count(db) == 3
