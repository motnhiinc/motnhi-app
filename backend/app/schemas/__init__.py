from pydantic import BaseModel


class DeviceAuthRequest(BaseModel):
    device_id: str


class DeviceAuthResponse(BaseModel):
    token: str
    user_id: str
