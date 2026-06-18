import pytest

from app.auth import create_token, decode_token


def test_token_roundtrip():
    token = create_token("user-123")
    assert decode_token(token) == "user-123"


def test_decode_rejects_garbage():
    with pytest.raises(Exception):
        decode_token("not-a-jwt")


def test_device_auth_registers_then_requires_secret(client):
    first = client.post("/v1/auth/device", json={"device_id": "device-abc"})
    assert first.status_code == 200
    body = first.json()
    assert body["token"] and body["user_id"] and body["device_secret"]

    again = client.post("/v1/auth/device",
                        json={"device_id": "device-abc", "device_secret": body["device_secret"]})
    assert again.status_code == 200
    assert again.json()["user_id"] == body["user_id"]
    assert again.json()["device_secret"] is None

    assert client.post("/v1/auth/device", json={"device_id": "device-abc"}).status_code == 401
    assert client.post("/v1/auth/device",
                       json={"device_id": "device-abc", "device_secret": "wrong"}).status_code == 401
