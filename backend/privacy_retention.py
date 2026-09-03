"""Privacy retention command: delete child data for inactive owners.

Selects users whose privacy_settings.last_active_at is strictly older than
the 90-day cutoff AND who still own child data (a child profile or an
authored story). Each candidate is processed in its own independent session:
lock the user row, re-check activity under the lock, then delete through the
shared child-data deletion service. One user's failure does not stop the
rest; in dry-run mode nothing is committed and `deleted` counts candidates
that would have been deleted.
"""
import argparse
import sys
from datetime import timedelta

from app.db import SessionLocal
from app.repositories import privacy as privacy_repo
from app.services.child_data_deletion import delete_child_data
from app.services.privacy import lock_user, utc_now

RETENTION_DAYS = 90


def run_retention(dry_run: bool, session_factory=None, now=None) -> int:
    session_factory = session_factory or SessionLocal
    now = now or utc_now()
    cutoff = now - timedelta(days=RETENTION_DAYS)

    selection_db = session_factory()
    try:
        candidate_ids = privacy_repo.retention_candidate_ids(selection_db, cutoff)
    finally:
        selection_db.close()

    attempted = deleted = skipped = failed = 0
    for user_id in candidate_ids:
        attempted += 1
        try:
            db = session_factory()
        except Exception:
            failed += 1
            continue
        try:
            lock_user(db, user_id)
            settings = privacy_repo.get_settings(db, user_id)
            if settings is None or not settings.last_active_at < cutoff:
                skipped += 1
                db.rollback()
                continue
            delete_child_data(db, user_id)
            if dry_run:
                db.rollback()
            else:
                db.commit()
            deleted += 1
        except Exception:
            db.rollback()
            failed += 1
        finally:
            db.close()

    print(
        f"attempted={attempted} deleted={deleted} skipped={skipped} "
        f"failed={failed} dry_run={'true' if dry_run else 'false'}"
    )
    return 0 if failed == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="select and report candidates without deleting anything",
    )
    args = parser.parse_args()
    return run_retention(dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
