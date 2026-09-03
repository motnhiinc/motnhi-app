from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.db import get_db
from app.models import User
from app.repositories import privacy as privacy_repo
from app.schemas import PrivacyStateResponse, PrivacyUpdateRequest
from app.services import child_data_deletion
from app.services import privacy as privacy_service

router = APIRouter(prefix="/v1/privacy", tags=["privacy"])


def _build_response(db: Session, user_id: str) -> PrivacyStateResponse:
    settings = privacy_repo.get_settings(db, user_id)
    return PrivacyStateResponse(
        current_policy_version=privacy_service.CURRENT_PRIVACY_POLICY_VERSION,
        accepted_policy_version=settings.accepted_policy_version,
        review_required=(
            settings.accepted_policy_version
            != privacy_service.CURRENT_PRIVACY_POLICY_VERSION
        ),
        core_storage_accepted_at=settings.core_storage_accepted_at,
        progress_tracking_enabled=settings.progress_tracking_enabled,
        cloud_tts_enabled=settings.cloud_tts_enabled,
        effective_progress_tracking_enabled=privacy_service.effective_progress(settings),
        effective_cloud_tts_enabled=privacy_service.effective_cloud_tts(settings),
        last_active_at=settings.last_active_at,
        updated_at=settings.updated_at,
        counts=privacy_repo.data_counts(db, user_id),
    )


@router.get("", response_model=PrivacyStateResponse)
def get_privacy_state(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> PrivacyStateResponse:
    privacy_service.lock_user(db, user.id)
    settings = privacy_repo.get_settings(db, user.id)
    if settings is None:
        privacy_repo.create_default_settings(db, user.id, privacy_service.utc_now())
        db.commit()
    return _build_response(db, user.id)


@router.put("", response_model=PrivacyStateResponse)
def update_privacy_state(
    body: PrivacyUpdateRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> PrivacyStateResponse:
    try:
        privacy_service.update_settings(
            db,
            user.id,
            policy_version=body.policy_version,
            core_storage_accepted=body.core_storage_accepted,
            progress_tracking_enabled=body.progress_tracking_enabled,
            cloud_tts_enabled=body.cloud_tts_enabled,
        )
        db.commit()
    except privacy_service.PrivacyError as error:
        db.rollback()
        raise HTTPException(status_code=error.status_code, detail=error.code)
    return _build_response(db, user.id)


@router.post("/activity", status_code=204)
def report_privacy_activity(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    try:
        if privacy_service.touch_activity_if_due(db, user.id, privacy_service.utc_now()):
            db.commit()
    except privacy_service.PrivacyError as error:
        db.rollback()
        raise HTTPException(status_code=error.status_code, detail=error.code)
    return Response(status_code=204)


@router.delete("/reading-history", status_code=204)
def delete_reading_history(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    try:
        privacy_service.lock_user(db, user.id)
        privacy_service.delete_reading_history(db, user.id)
        db.commit()
    except privacy_service.PrivacyError as error:
        db.rollback()
        raise HTTPException(status_code=error.status_code, detail=error.code)
    return Response(status_code=204)


@router.delete("/child-data", status_code=204)
def delete_child_data(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    try:
        privacy_service.lock_user(db, user.id)
        child_data_deletion.delete_child_data(db, user.id)
        db.commit()
    except privacy_service.PrivacyError as error:
        db.rollback()
        raise HTTPException(status_code=error.status_code, detail=error.code)
    return Response(status_code=204)
