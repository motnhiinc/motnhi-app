import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import create_token, generate_secret, hash_secret, verify_secret
from app.db import get_db
from app.models import Device, User
from app.schemas import DeviceAuthRequest, DeviceAuthResponse

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post("/device", response_model=DeviceAuthResponse)
def device_auth(body: DeviceAuthRequest, db: Session = Depends(get_db)) -> DeviceAuthResponse:
    device = db.scalar(select(Device).where(Device.device_id == body.device_id))
    if device is None:
        now = datetime.now(timezone.utc)
        secret = generate_secret()
        user = User(id=str(uuid.uuid4()), auth_provider="device", created_at=now, updated_at=now)
        db.add(user)
        db.flush()
        device = Device(id=str(uuid.uuid4()), device_id=body.device_id, user_id=user.id,
                        secret_hash=hash_secret(secret), created_at=now)
        db.add(device)
        db.commit()
        return DeviceAuthResponse(token=create_token(user.id), user_id=user.id, device_secret=secret)
    if not body.device_secret or not verify_secret(body.device_secret, device.secret_hash):
        raise HTTPException(status_code=401, detail="invalid device credentials")
    return DeviceAuthResponse(token=create_token(device.user_id), user_id=device.user_id)
