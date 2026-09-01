from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import PrivacySettings, User
from app.repositories import privacy as privacy_repo

CURRENT_PRIVACY_POLICY_VERSION = "2026-08-28"


class PrivacyError(Exception):
    def __init__(self, status_code: int, code: str):
        super().__init__(code)
        self.status_code = status_code
        self.code = code


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def lock_user(db: Session, user_id: str) -> User:
    user = db.scalar(
        select(User).where(User.id == user_id).with_for_update()
    )
    if user is None:
        raise PrivacyError(401, "unknown_user")
    return user


def effective_progress(settings: PrivacySettings | None) -> bool:
    return bool(
        settings
        and settings.accepted_policy_version == CURRENT_PRIVACY_POLICY_VERSION
        and settings.progress_tracking_enabled
    )


def effective_cloud_tts(settings: PrivacySettings | None) -> bool:
    return bool(
        settings
        and settings.accepted_policy_version == CURRENT_PRIVACY_POLICY_VERSION
        and settings.cloud_tts_enabled
    )


def require_core_storage(settings: PrivacySettings | None) -> None:
    if (
        settings is None
        or settings.accepted_policy_version != CURRENT_PRIVACY_POLICY_VERSION
    ):
        raise PrivacyError(428, "privacy_policy_review_required")


def require_progress(settings: PrivacySettings | None) -> None:
    if not effective_progress(settings):
        raise PrivacyError(403, "progress_tracking_disabled")


def require_cloud_tts(settings: PrivacySettings | None) -> None:
    if not effective_cloud_tts(settings):
        raise PrivacyError(403, "cloud_tts_disabled")


def update_settings(
    db: Session,
    user_id: str,
    *,
    policy_version: str,
    core_storage_accepted: bool,
    progress_tracking_enabled: bool,
    cloud_tts_enabled: bool,
) -> PrivacySettings:
    if (
        policy_version != CURRENT_PRIVACY_POLICY_VERSION
        or not core_storage_accepted
    ):
        raise PrivacyError(428, "privacy_policy_review_required")

    lock_user(db, user_id)
    now = utc_now()
    settings = privacy_repo.get_settings(db, user_id)
    if settings is None:
        settings = privacy_repo.create_default_settings(db, user_id, now)

    accepts_new_policy = settings.accepted_policy_version != policy_version
    progress_changed = (
        settings.progress_tracking_enabled != progress_tracking_enabled
    )
    cloud_tts_changed = settings.cloud_tts_enabled != cloud_tts_enabled

    if accepts_new_policy:
        settings.core_storage_accepted_at = now
        events = (
            ("core_storage", True),
            ("progress_tracking", progress_tracking_enabled),
            ("cloud_tts", cloud_tts_enabled),
        )
    else:
        events = []
        if progress_changed:
            events.append(("progress_tracking", progress_tracking_enabled))
        if cloud_tts_changed:
            events.append(("cloud_tts", cloud_tts_enabled))

    settings.accepted_policy_version = policy_version
    settings.progress_tracking_enabled = progress_tracking_enabled
    settings.cloud_tts_enabled = cloud_tts_enabled
    settings.last_active_at = now
    settings.updated_at = now

    for scope, granted in events:
        privacy_repo.add_event(
            db,
            user_id,
            scope,
            granted,
            policy_version,
            now,
        )

    db.flush()
    return settings
