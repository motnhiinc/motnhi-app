from pydantic import BaseModel


class DeviceAuthRequest(BaseModel):
    device_id: str
    device_secret: str | None = None


class DeviceAuthResponse(BaseModel):
    token: str
    user_id: str
    device_secret: str | None = None  # set ONLY on first registration
