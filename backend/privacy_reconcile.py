"""Privacy reconciliation command: backfill default privacy settings rows.

Every user must have exactly one privacy_settings row. Missing rows are
inserted with the default (pre-consent) state in a single transaction, then
the one-row-per-user invariant is verified. Exits nonzero when the invariant
does not hold.
"""
import sys

from sqlalchemy import func, select

from app.db import SessionLocal
from app.models import PrivacySettings, User
from app.repositories import privacy as privacy_repo
from app.services.privacy import utc_now


def run_reconcile(session_factory=None, now=None) -> int:
    session_factory = session_factory or SessionLocal
    now = now or utc_now()

    db = session_factory()
    try:
        missing_user_ids = privacy_repo.missing_privacy_user_ids(db)
        for user_id in missing_user_ids:
            privacy_repo.create_default_settings(db, user_id, now)
        db.commit()
        users = db.scalar(select(func.count()).select_from(User))
        privacy_rows = db.scalar(select(func.count()).select_from(PrivacySettings))
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

    print(f"created={len(missing_user_ids)} users={users} privacy_rows={privacy_rows}")
    return 0 if users == privacy_rows else 1


if __name__ == "__main__":
    sys.exit(run_reconcile())
